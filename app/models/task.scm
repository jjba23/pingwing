(import (artanis mvc model))

(create-artanis-model task
                      (:deps)
                      (id char-field
                          (#:unique #:not-null #:maxlen 36))
                      (task_status char-field
                                   (#:not-null #:maxlen 256))
                      (task_type char-field
                                 (#:not-null #:maxlen 256))
                      (template char-field
                                (#:not-null #:maxlen 256))
                      (template_vars char-field
                                     (#:maxlen 40960))
                      (sender_name char-field
                                   (#:maxlen 512))
                      (sender_address char-field
                                      (#:maxlen 512))
                      (subject char-field
                               (#:maxlen 512))
                      (recipients char-field
                                  (#:maxlen 24576))
                      (created_at date-field
                                  (#:not-null))
                      (updated_at date-field)
                      (attempts bigint))

