-- pingwing - the free and open Lisp-powered notification nexus

-- Copyright © Josep Bigorra <jjbigorra@gmail.com>

-- pingwing is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- Put the task text back the way the caller wrote it.
--
-- Rows written before pingwing bound its SQL values were escaped on the way
-- in: an apostrophe became `&apos;' and a double quote `&quot;', which is what
-- kept a quote from ending a SQL literal early.  Binding removes the need for
-- that -- a value is a value, and no escaping is applied on the way in or out
-- any more -- so what earlier rows still carry is an artifact of how they were
-- stored, and this is the migration that takes it back off.
--
-- The two replacements are exact inverses of the two the insert path applied,
-- and in the order that inverts it: `&quot;' is undone first, since undoing
-- `&apos;' first would leave an escaped quote behind in a value that had one.
-- The same escaping was applied to these six columns and no others.

UPDATE "tasks"
SET "template"       = REPLACE(REPLACE("template", '&quot;', '"'), '&apos;', ''''),
    "template_vars"  = REPLACE(REPLACE("template_vars", '&quot;', '"'), '&apos;', ''''),
    "sender_name"    = REPLACE(REPLACE("sender_name", '&quot;', '"'), '&apos;', ''''),
    "sender_address" = REPLACE(REPLACE("sender_address", '&quot;', '"'), '&apos;', ''''),
    "subject"        = REPLACE(REPLACE("subject", '&quot;', '"'), '&apos;', ''''),
    "recipients"     = REPLACE(REPLACE("recipients", '&quot;', '"'), '&apos;', '''');
