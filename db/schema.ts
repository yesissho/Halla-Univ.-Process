import {sqliteTable,text,integer} from 'drizzle-orm/sqlite-core';
export const employees=sqliteTable('employees',{id:text('id').primaryKey(),salt:text('salt').notNull(),hash:text('hash').notNull(),role:text('role').notNull(),enabled:integer('enabled').notNull(),mustChange:integer('must_change').notNull(),createdAt:integer('created_at').notNull()});
export const sessions=sqliteTable('sessions',{token:text('token').primaryKey(),employee:text('employee').notNull(),expires:integer('expires').notNull()});
export const attempts=sqliteTable('login_attempts',{key:text('key').primaryKey(),count:integer('count').notNull(),until:integer('until').notNull()});

// Separate from the retired administrator-issued login; no legacy credentials migrate.
export const members=sqliteTable('member_accounts',{employee:text('employee').primaryKey(),salt:text('salt').notNull(),passwordHash:text('password_hash').notNull(),createdAt:integer('created_at').notNull()});
export const memberSessions=sqliteTable('member_sessions',{tokenHash:text('token_hash').primaryKey(),employee:text('employee').notNull().references(()=>members.employee),expiresAt:integer('expires_at').notNull()});
export const memberState=sqliteTable('member_state',{employee:text('employee').primaryKey().references(()=>members.employee),payload:text('payload').notNull(),revision:integer('revision').notNull(),updatedAt:integer('updated_at').notNull()});
export const memberLimits=sqliteTable('member_limits',{key:text('key').primaryKey(),count:integer('count').notNull(),resetAt:integer('reset_at').notNull()});
