CREATE TABLE "tasks" (
	"id"	VARCHAR(36) NOT NULL,
	"task_status"	TEXT NOT NULL,
	"task_type"	TEXT NOT NULL,
  "template" TEXT NOT NULL,
  "template_vars" TEXT NOT NULL,
  "sender_name" TEXT NOT NULL,
  "sender_address" TEXT NOT NULL,
  "subject" TEXT NOT NULL,
  "recipients" TEXT NOT NULL,
  "attempts" INT NOT NULL DEFAULT 0,
	"created_at"	DATE NOT NULL,
	"updated_at"	DATE,
	PRIMARY KEY("id")
);
