import {readFileSync,writeFileSync,mkdirSync,rmSync} from 'node:fs';
import {createHash} from 'node:crypto';
const read=p=>readFileSync(p,'utf8'),hash=s=>createHash('sha256').update(s).digest('hex').slice(0,12);
const app=read('src/app.js'),style=read('src/style.css'),appName=`app-${hash(app)}.js`,styleName=`style-${hash(style)}.css`;
const asset=(body,type)=>({body,type});
const assets={'/index.html':asset(read('src/index.html').replaceAll('{{APP_FILE}}',appName).replaceAll('{{STYLE_FILE}}',styleName),'text/html;charset=utf-8'),['/'+appName]:asset(app,'text/javascript;charset=utf-8'),['/'+styleName]:asset(style,'text/css;charset=utf-8'),'/login.html':asset(read('src/login.html'),'text/html;charset=utf-8'),'/auth.js':asset(read('src/auth.js'),'text/javascript;charset=utf-8'),'/auth.css':asset(read('src/auth.css'),'text/css;charset=utf-8'),'/campus.svg':asset(read('src/campus.svg'),'image/svg+xml')};
rmSync('dist',{recursive:true,force:true});mkdirSync('dist/server',{recursive:true});
writeFileSync('dist/server/index.js',read('worker/index.js').replace("import {assets} from './assets.js';",'const assets='+JSON.stringify(assets)+';'));
console.log('Built authenticated Worker and dashboard assets');
