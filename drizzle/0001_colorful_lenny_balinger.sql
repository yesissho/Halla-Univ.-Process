CREATE TABLE `member_limits` (
	`key` text PRIMARY KEY NOT NULL,
	`count` integer NOT NULL,
	`reset_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `member_sessions` (
	`token_hash` text PRIMARY KEY NOT NULL,
	`employee` text NOT NULL,
	`expires_at` integer NOT NULL,
	FOREIGN KEY (`employee`) REFERENCES `member_accounts`(`employee`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `member_state` (
	`employee` text PRIMARY KEY NOT NULL,
	`payload` text NOT NULL,
	`revision` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`employee`) REFERENCES `member_accounts`(`employee`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `member_accounts` (
	`employee` text PRIMARY KEY NOT NULL,
	`salt` text NOT NULL,
	`password_hash` text NOT NULL,
	`created_at` integer NOT NULL
);
