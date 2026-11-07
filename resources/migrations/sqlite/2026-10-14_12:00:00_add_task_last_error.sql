-- pingwing - the free and open Lisp-powered notification nexus
--
-- SPDX-License-Identifier: MIT
-- Copyright © Josep Bigorra <jjbigorra@gmail.com>

-- Record why a task did not go out.
--
-- A delivery that fails now has somewhere to say so: the queue worker writes
-- the SMTP server's own answer here when a task is requeued or given up on, so
-- `maak migrate` and a look at the tasks table are enough to see what a
-- deployment's mail is doing.  Empty for a task that succeeded.

ALTER TABLE tasks ADD COLUMN last_error TEXT;
