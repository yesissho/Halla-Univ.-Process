import sys, tempfile, traceback, ctypes
from ctypes import wintypes
from pathlib import Path
from PySide6.QtCore import QThread, Signal, QAbstractNativeEventFilter, QTimer
from PySide6.QtWidgets import QApplication, QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QListWidget, QComboBox, QFileDialog, QMessageBox, QTextEdit, QSystemTrayIcon, QMenu, QStyle

SUPPORTED = {'.pdf', '.hwp', '.hwpx', '.xls', '.xlsx', '.xlsm'}

def convert(source, dest):
    import win32com.client
    if source.suffix.lower() == '.pdf':
        return source
    if source.suffix.lower() in {'.hwp', '.hwpx'}:
        hwp = win32com.client.DispatchEx('HWPFrame.HwpObject')
        try:
            if not hwp.Open(str(source), '', 'forceopen:true'):
                raise RuntimeError('한글 파일을 열지 못했습니다. 보안 확인창이 있으면 확인하세요.')
            # Use the HWP PDF print action explicitly: SaveAs inherits saved N-up.
            action = hwp.CreateAction('PrintToPDFEx')
            params = action.CreateSet()
            action.GetDefault(params)
            for key, value in {
                'FileName': str(dest), 'PrinterName': 'Hancom PDF',
                'PrintMethod': 0, 'Range': 0, 'NumCopy': 1,
                'Collate': 1, 'UserOrder': 0, 'ReverseOrder': 0,
                'Pause': 0, 'PrintToFile': 0,
            }.items():
                params.SetItem(key, value)
            if not action.Execute(params):
                raise RuntimeError('한글 기본 인쇄 PDF 변환에 실패했습니다. Hancom PDF 설치 상태를 확인하세요.')
        finally:
            hwp.Quit()
    else:
        excel = win32com.client.DispatchEx('Excel.Application')
        book = None
        try:
            excel.Visible = False
            excel.DisplayAlerts = False
            excel.AutomationSecurity = 3
            book = excel.Workbooks.Open(str(source), UpdateLinks=0, ReadOnly=True)
            # Export all visible sheets, ignoring saved print-area restrictions.
            book.ExportAsFixedFormat(Type=0, Filename=str(dest), Quality=0,
                IncludeDocProperties=False, IgnorePrintAreas=True, OpenAfterPublish=False)
        finally:
            if book is not None:
                book.Close(SaveChanges=False)
            excel.Quit()
    if not dest.is_file() or dest.stat().st_size == 0:
        raise RuntimeError('PDF 변환 결과가 없습니다.')
    return dest

def validated_devmode(printer, orientation):
    import subprocess
    with tempfile.TemporaryDirectory(prefix='QuickPrint-settings-') as folder:
        dest = Path(folder) / 'devmode.bin'
        result = subprocess.run([
            'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', str(Path(__file__).with_name('print-settings.ps1')),
            '-Printer', printer, '-Destination', str(dest), '-Orientation', orientation,
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60,
            creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode or not dest.is_file():
            error = result.stderr.decode('utf-8', errors='replace')
            raise RuntimeError('프린터 설정 준비에 실패했습니다.\n' + error)
        data = dest.read_bytes()
        if len(data) < 220:
            raise RuntimeError('프린터 설정 데이터가 올바르지 않아 인쇄를 중단했습니다.')
        return data

def print_pdf(path, printer, cancelled, report):
    import pymupdf, win32print, win32gui, win32ui, win32con
    from PIL import Image, ImageWin
    with pymupdf.open(path) as doc:
        if doc.needs_pass:
            raise RuntimeError('암호가 걸린 PDF는 잠금을 해제한 뒤 추가하세요.')
        settings = {}
        for page in doc:
            orientation = 'Landscape' if page.rect.width > page.rect.height else 'Portrait'
            if orientation not in settings:
                settings[orientation] = validated_devmode(printer, orientation)
        report('출력 설정 지정: 단면 · 흑백 · 기본 인쇄 · 1부 (일부 드라이버는 설정 확인값을 제공하지 않습니다)')
        for index, page in enumerate(doc):
            if cancelled():
                raise InterruptedError('중지됨: 이미 전송된 인쇄 작업은 프린터 대기열에서 취소하세요.')
            # One independent job per page: no two source pages can share a duplex sheet.
            handle = win32print.OpenPrinter(printer)
            dc = None
            started = False
            try:
                orientation = 'Landscape' if page.rect.width > page.rect.height else 'Portrait'
                dm_buffer = ctypes.create_string_buffer(settings[orientation])
                gdi = ctypes.WinDLL('gdi32', use_last_error=True)
                gdi.CreateDCW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.LPCWSTR, ctypes.c_void_p]
                gdi.CreateDCW.restype = wintypes.HDC
                raw_dc = gdi.CreateDCW('WINSPOOL', printer, None, dm_buffer)
                if not raw_dc:
                    raise RuntimeError('검증한 설정으로 프린터를 열지 못했습니다.')
                dc = win32ui.CreateDCFromHandle(raw_dc)
                w, h = dc.GetDeviceCaps(8), dc.GetDeviceCaps(10)
                if min(w, h) <= 0:
                    raise RuntimeError('인쇄 가능한 용지 크기를 확인할 수 없습니다.')
                pix = page.get_pixmap(dpi=300, colorspace=pymupdf.csGRAY, alpha=False)
                image = Image.frombytes('L', (pix.width, pix.height), pix.samples).convert('RGB')
                ratio = min(w / image.width, h / image.height)
                dw, dh = int(image.width * ratio), int(image.height * ratio)
                x, y = (w-dw)//2, (h-dh)//2
                dc.StartDoc(f'{path.stem} [{index+1}/{len(doc)}]')
                started = True
                dc.StartPage()
                ImageWin.Dib(image).draw(dc.GetHandleOutput(), (x, y, x+dw, y+dh))
                dc.EndPage()
                dc.EndDoc()
                started = False
                report(f'  {index+1}/{len(doc)} 페이지 전송')
            except Exception:
                if started:
                    dc.AbortDoc()
                raise
            finally:
                if dc is not None:
                    dc.DeleteDC()
                win32print.ClosePrinter(handle)

class Worker(QThread):
    log = Signal(str)
    def __init__(self, files, printer):
        super().__init__()
        self.files, self.printer = files, printer
        self.cancelled = False
    def run(self):
        import pythoncom
        pythoncom.CoInitialize()
        try:
            with tempfile.TemporaryDirectory(prefix='QuickPrint-') as folder:
                for n, name in enumerate(self.files):
                    if self.cancelled:
                        break
                    source = Path(name)
                    self.log.emit(f'처리 중: {source.name}')
                    if source.suffix.lower() in {'.hwp', '.hwpx'}:
                        self.log.emit('한글: 모두 · 1매 · 기본 인쇄/자동 인쇄로 PDF 변환')
                    try:
                        pdf = convert(source, Path(folder) / f'{n}-{source.stem}.pdf')
                        print_pdf(pdf, self.printer, lambda: self.cancelled, self.log.emit)
                        self.log.emit(f'전송 완료: {source.name}')
                    except InterruptedError as e:
                        self.log.emit(str(e))
                        break
                    except Exception as e:
                        self.log.emit(f'실패: {source.name}\n{e}')
                        self.log.emit('추가 인쇄를 멈췄습니다. 이미 전송된 페이지를 확인한 뒤 재시도하세요.')
                        break
        except Exception as e:
            self.log.emit(f'오류: {e}')
        finally:
            pythoncom.CoUninitialize()

class Window(QWidget):
    def __init__(self):
        super().__init__()
        self.worker = None
        self.setWindowTitle('간편 인쇄 1.0.7')
        self.resize(760, 640)
        self.setAcceptDrops(True)
        layout = QVBoxLayout(self)
        title = QLabel('간편 인쇄')
        title.setStyleSheet('font-size:28px;font-weight:700;')
        layout.addWidget(title)
        layout.addWidget(QLabel('탐색기에서 파일 선택 → Ctrl+Alt+P로 목록에 추가\n이 창은 최소화해 두어도 됩니다. 파일 끌어넣기도 지원합니다.'))
        layout.addWidget(QLabel('단면  |  흑백  |  전체 페이지  |  1장에 1페이지  |  1부'))
        self.printers = QComboBox()
        import win32print
        names = [p[2] for p in win32print.EnumPrinters(6)]
        self.printers.addItems(names)
        try:
            self.printers.setCurrentText(win32print.GetDefaultPrinter())
        except Exception:
            pass
        layout.addWidget(self.printers)
        self.items = QListWidget()
        self.items.setSelectionMode(QListWidget.ExtendedSelection)
        layout.addWidget(self.items, 2)
        self.count_label = QLabel('이번에 추가 0개 · 전체 0개')
        layout.addWidget(self.count_label)
        self.items.model().rowsRemoved.connect(lambda *args: self.update_count())
        self.items.model().modelReset.connect(lambda *args: self.update_count())
        buttons = QHBoxLayout()
        self.add = QPushButton('파일 추가')
        self.remove = QPushButton('선택 삭제')
        self.clear = QPushButton('목록 비우기')
        self.go = QPushButton('인쇄')
        self.go.setStyleSheet('background:#2563eb;color:white;font-weight:700;')
        self.stop = QPushButton('중지')
        self.stop.setEnabled(False)
        for button in (self.add,self.remove,self.clear,self.go,self.stop):
            buttons.addWidget(button)
        layout.addLayout(buttons)
        self.logs = QTextEdit()
        self.logs.setReadOnly(True)
        layout.addWidget(self.logs, 1)
        layout.addWidget(QLabel('엑셀: 표시된 모든 시트 · 저장된 인쇄영역 무시 · 기존 배율/용지 설정 유지\n한글·엑셀은 해당 데스크톱 프로그램 필요. 한글 보안 확인창이 뜨면 확인하세요.'))
        self.add.clicked.connect(self.choose)
        self.remove.clicked.connect(self.remove_selected)
        self.clear.clicked.connect(self.items.clear)
        self.go.clicked.connect(self.start)
        self.stop.clicked.connect(self.cancel)
        self.hotkey_hwnd = int(self.winId())
        self.user32 = ctypes.WinDLL('user32', use_last_error=True)
        self.user32.RegisterHotKey.argtypes = [wintypes.HWND, ctypes.c_int, wintypes.UINT, wintypes.UINT]
        self.user32.RegisterHotKey.restype = wintypes.BOOL
        self.user32.UnregisterHotKey.argtypes = [wintypes.HWND, ctypes.c_int]
        self.hotkey_registered = bool(self.user32.RegisterHotKey(self.hotkey_hwnd, 7301, 0x4003, 0x50))
        self.hotkey_status = QLabel('단축키 준비 완료: Ctrl+Alt+P' if self.hotkey_registered else '단축키 등록 실패: 기존 간편인쇄 창을 닫고 다시 실행하세요.')
        layout.addWidget(self.hotkey_status)
        QApplication.instance().aboutToQuit.connect(self.unregister_hotkey)
    def nativeEvent(self, event_type, message):
        msg = wintypes.MSG.from_address(int(message))
        if msg.message == 0x0312 and msg.wParam == 7301:
            import win32gui
            foreground = win32gui.GetForegroundWindow()
            QTimer.singleShot(0, lambda: self.print_explorer_selection(foreground))
            return True, 0
        return super().nativeEvent(event_type, message)
    def unregister_hotkey(self):
        if self.hotkey_registered:
            self.user32.UnregisterHotKey(self.hotkey_hwnd, 7301)
            self.hotkey_registered = False
    def print_explorer_selection(self, foreground=None):
        if self.worker and self.worker.isRunning():
            self.logs.append('현재 인쇄 처리 중입니다. 완료 후 단축키를 눌러주세요.')
            return
        import win32gui, win32com.client
        foreground = foreground or win32gui.GetForegroundWindow()
        try:
            shell = win32com.client.Dispatch('Shell.Application')
            selected = None
            for explorer in shell.Windows():
                try:
                    if int(explorer.HWND) == foreground:
                        selected = [str(item.Path) for item in explorer.Document.SelectedItems()]
                        break
                except Exception:
                    continue
            if selected is None:
                raise RuntimeError('파일 탐색기 창에서 파일을 선택한 상태로 Ctrl+Alt+P를 눌러주세요. 바탕화면 선택은 지원하지 않습니다.')
            if not selected:
                raise RuntimeError('선택된 파일이 없습니다.')
            missing = [name for name in selected if not Path(name).is_file()]
            if missing:
                raise RuntimeError('압축파일 내부 또는 가상 폴더 파일은 바로 인쇄할 수 없습니다. 압축을 풀고 일반 폴더에서 다시 선택하세요.')
            unsupported = [name for name in selected if Path(name).suffix.lower() not in SUPPORTED]
            if unsupported:
                raise RuntimeError('한글·PDF·엑셀 파일만 선택하세요. 지원하지 않는 파일: ' + ', '.join(Path(x).name for x in unsupported))
            if not self.printers.currentText():
                raise RuntimeError('간편 인쇄 창에서 프린터를 먼저 선택하세요.')
            self.add_files(selected)
            self.showNormal()
            self.raise_()
            self.activateWindow()
        except Exception as e:
            QMessageBox.warning(self, '탐색기 선택 인쇄', str(e))
    def choose(self):
        files,_ = QFileDialog.getOpenFileNames(self,'인쇄할 파일 선택','','문서 (*.pdf *.hwp *.hwpx *.xls *.xlsx *.xlsm)')
        self.add_files(files)
    def update_count(self, added=0, duplicate=0, skipped=0):
        self.count_label.setText(f'이번에 추가 {added}개 · 전체 {self.items.count()}개 · 중복 {duplicate}개 · 제외 {skipped}개')
    def add_files(self, paths):
        existing = {Path(self.items.item(i).text()).name.casefold() for i in range(self.items.count())}
        added = duplicate = skipped = 0
        for name in paths:
            p = Path(name).resolve()
            if p.is_file() and p.suffix.lower() in SUPPORTED:
                if p.name.casefold() in existing:
                    duplicate += 1
                    self.showNormal()
                    self.raise_()
                    self.activateWindow()
                    prompt = QMessageBox(self)
                    prompt.setWindowTitle('같은 파일명 확인')
                    prompt.setIcon(QMessageBox.Question)
                    prompt.setText(f'목록에 같은 파일명이 있습니다.\n{p.name}\n\n한 번 더 추가할까요?')
                    prompt.setInformativeText(f'추가할 파일: {p}\n추가하면 인쇄 버튼을 누를 때 이 항목도 별도로 출력됩니다.')
                    yes = prompt.addButton('추가', QMessageBox.AcceptRole)
                    no = prompt.addButton('건너뛰기', QMessageBox.RejectRole)
                    prompt.setDefaultButton(no)
                    prompt.exec()
                    if prompt.clickedButton() != yes:
                        skipped += 1
                        continue
                self.items.addItem(str(p))
                existing.add(p.name.casefold())
                added += 1
            else:
                skipped += 1
                self.logs.append(f'지원하지 않는 파일: {p.name}')
        self.update_count(added, duplicate, skipped)
        self.logs.append(f'목록 추가 {added}개 / 전체 {self.items.count()}개 (중복 {duplicate}개, 제외 {skipped}개)')
    def remove_selected(self):
        for item in self.items.selectedItems():
            self.items.takeItem(self.items.row(item))
    def dragEnterEvent(self,event):
        if event.mimeData().hasUrls() and not (self.worker and self.worker.isRunning()):
            event.acceptProposedAction()
    def dropEvent(self,event):
        self.add_files([u.toLocalFile() for u in event.mimeData().urls() if u.isLocalFile()])
        event.acceptProposedAction()
    def start(self):
        if not self.items.count() or not self.printers.currentText():
            QMessageBox.information(self,'확인','파일과 프린터를 선택하세요.')
            return
        self.logs.clear()
        self.busy(True)
        self.worker = Worker([self.items.item(i).text() for i in range(self.items.count())],self.printers.currentText())
        self.worker.log.connect(self.logs.append)
        self.worker.finished.connect(lambda: self.busy(False))
        self.worker.start()
    def busy(self,value):
        for widget in (self.add,self.remove,self.clear,self.go,self.printers,self.items):
            widget.setEnabled(not value)
        self.stop.setEnabled(value)
    def cancel(self):
        self.worker.cancelled = True
        self.logs.append('중지 요청: 현재 페이지/변환이 끝나면 멈춥니다. 전송된 작업은 프린터 대기열에서 취소하세요.')
    def open_window(self):
        self.showNormal()
        self.raise_()
        self.activateWindow()
    def setup_tray(self):
        self.tray = QSystemTrayIcon(self)
        self.tray.setIcon(self.style().standardIcon(QStyle.SP_ComputerIcon))
        self.tray.setToolTip('간편 인쇄 · Ctrl+Alt+P로 목록 추가')
        self.tray_menu = QMenu(self)
        self.tray_menu.addAction('간편 인쇄 열기', self.open_window)
        self.tray_menu.addSeparator()
        self.tray_menu.addAction('완전히 종료', self.quit_app)
        self.tray.setContextMenu(self.tray_menu)
        self.tray.activated.connect(self.tray_activated)
        self.tray.show()
    def tray_activated(self, reason):
        if reason in (QSystemTrayIcon.Trigger, QSystemTrayIcon.DoubleClick):
            self.open_window()
    def quit_app(self):
        if self.worker and self.worker.isRunning():
            self.open_window()
            QMessageBox.information(self, '인쇄 처리 중', '중지 버튼을 누르고 처리가 끝난 뒤 종료하세요.')
            return
        self.unregister_hotkey()
        self.tray.hide()
        QApplication.instance().quit()
    def closeEvent(self,event):
        if QSystemTrayIcon.isSystemTrayAvailable():
            event.ignore()
            self.hide()
        elif self.worker and self.worker.isRunning():
            event.ignore()
            QMessageBox.information(self, '인쇄 처리 중', '처리가 끝난 뒤 종료하세요.')
        else:
            event.accept()
            QApplication.instance().quit()

if __name__ == '__main__':
    # Retain the handle for the process lifetime to prevent duplicate startup copies.
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateMutexW.argtypes = [ctypes.c_void_p, wintypes.BOOL, wintypes.LPCWSTR]
    kernel.CreateMutexW.restype = wintypes.HANDLE
    instance_mutex = kernel.CreateMutexW(None, False, 'Local\\EunQuickPrint')
    already_running = ctypes.get_last_error() == 183
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    if not instance_mutex:
        QMessageBox.warning(None, '간편 인쇄', '프로그램 실행 상태를 확인하지 못했습니다.')
        sys.exit(1)
    if already_running:
        if '--tray' not in sys.argv:
            QMessageBox.information(None, '간편 인쇄', '이미 실행 중입니다. 작업표시줄 오른쪽 숨겨진 아이콘에서 간편 인쇄를 누르세요.')
        sys.exit(0)
    app.setStyleSheet('QWidget{font-family:"Malgun Gothic";font-size:13px;} QPushButton{padding:10px;} QListWidget,QTextEdit{background:#f7f9fc;border:1px solid #d5dce8;border-radius:6px;}')
    window = Window()
    window.setup_tray()
    if '--tray' not in sys.argv or not QSystemTrayIcon.isSystemTrayAvailable():
        window.show()
    sys.exit(app.exec())
