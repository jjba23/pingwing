(import (artanis mvc model))

(create-artanis-model task
                      (:deps)
                      (id char-field
                          (#:unique #:not-null #:maxlen 36))
                      (task_status char-field
                                   (#:not-null #:maxlen 256))
                      (task_type char-field
                                 (#:not-null #:maxlen 256))
                      (sender char-field
                              (#:maxlen 512))
                      (subject char-field
                               (#:maxlen 512))
                      (recipients char-field
                                  (#:not-null #:maxlen 24576
                                   #:unique))
                      (body char-field
                            (#:not-null #:maxlen 40960))
                      (created_at date-field
                                  (#:not-null))
                      (updated_at date-field))

