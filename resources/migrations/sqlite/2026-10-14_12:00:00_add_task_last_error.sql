-- pingwing - the free and open Lisp-powered notification nexus

-- Copyright © Josep Bigorra <jjbigorra@gmail.com>

-- pingwing is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- Record why a task did not go out.
--
-- A delivery that fails now has somewhere to say so: the queue worker writes
-- the SMTP server's own answer here when a task is requeued or given up on, so
-- `maak migrate` and a look at the tasks table are enough to see what a
-- deployment's mail is doing.  Empty for a task that succeeded.

ALTER TABLE tasks ADD COLUMN last_error TEXT;
