CREATE TABLE `login_attempts` (
	`key` text PRIMARY KEY NOT NULL,
	`count` integer NOT NULL,
	`until` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `employees` (
	`id` text PRIMARY KEY NOT NULL,
	`salt` text NOT NULL,
	`hash` text NOT NULL,
	`role` text NOT NULL,
	`enabled` integer NOT NULL,
	`must_change` integer NOT NULL,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `sessions` (
	`token` text PRIMARY KEY NOT NULL,
	`employee` text NOT NULL,
	`expires` integer NOT NULL
);
