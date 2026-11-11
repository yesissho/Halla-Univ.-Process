import {DatabaseSync} from 'node:sqlite';
import {readFileSync,readdirSync} from 'node:fs';
export function database(filename=':memory:'){
 const sql=new DatabaseSync(filename);sql.exec('PRAGMA foreign_keys=ON');
 sql.exec('CREATE TABLE IF NOT EXISTS local_migrations (name TEXT PRIMARY KEY)');
 for(const name of readdirSync('drizzle').filter(n=>n.endsWith('.sql')).sort()){if(!sql.prepare('SELECT name FROM local_migrations WHERE name=?').get(name)){sql.exec(readFileSync('drizzle/'+name,'utf8'));sql.prepare('INSERT INTO local_migrations VALUES (?)').run(name);}}
 const make=(query,args=[])=>({bind(...values){return make(query,values)},async first(){return sql.prepare(query).get(...args)||null},async run(){return sql.prepare(query).run(...args)},async all(){return {results:sql.prepare(query).all(...args)}},query,args});
 return {sql,prepare:make,async batch(statements){sql.exec('BEGIN');try{const out=[];for(const s of statements)out.push(sql.prepare(s.query).run(...s.args));sql.exec('COMMIT');return out}catch(e){sql.exec('ROLLBACK');throw e}}};
}
