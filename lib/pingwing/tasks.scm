;;; pingwing

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; pingwing is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; pingwing is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with pingwing.  If not, see <https://www.gnu.org/licenses/>.

(define-module (pingwing tasks)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 iconv)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 string-fun)
  #:use-module (artanis db)
  #:use-module (artanis ssql)
  #:use-module (srfi srfi-64)
  #:use-module (pingwing process)
  #:use-module (pingwing query-escape)
  #:use-module (app models task))

;; sesAccess='AKIAXXXXXXXXXXXXXXXX'
;; sesSecret='Bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'   
;; sesFromName="Joe McJones"
;; sesFromAddress="joe.mcjones@fakeaddress.net"
;; sesToName="Mary McMary"
;; sesToAddress="mary.mcmary@notmyrealmail.com"
;; sesSubject="Test Email from Script"
;; sesSMTP="email-smtp.us-east-1.amazonaws.com"
;; sesPort="465"
;; sesMessage=$'Test of line 1\nTest of line 2'
;; sesFile="$1"
;; sesMIMEType=`file --mime-type "$sesFile" | sed 's/.*: //'`

;; curl -v --url smtps://$sesSMTP:$sesPort --ssl-reqd  --mail-from $sesFromAddress --mail-rcpt $sesToAddress  --user $sesAccess:$sesSecret -F '=(;type=multipart/mixed' -F "=$sesMessage;type=text/plain" -F "file=@$sesFile;type=$sesMIMEType;encoder=base64" -F '=)' -H "Subject: $sesSubject" -H "From: $sesFromName <$sesFromAddress>" -H "To: $sesToName <$sesToAddress>"

(define* (pingwing-send-mail #:key access-key
                             access-secret
                             access-server
                             access-port
                             from-name
                             from-address
                             to-name
                             to-address
                             subject
                             body)
  (display (format #f "\nsending mail to ~a" access-server)))

(define* (do-send-mail #:key task recipient pingwing-settings)
  (pingwing-send-mail #:access-key (assoc-ref (assoc-ref pingwing-settings
                                                         'mail)
                                              'access-key)
                      #:access-secret (assoc-ref (assoc-ref pingwing-settings
                                                            'mail)
                                                 'access-secret)
                      #:access-server (assoc-ref (assoc-ref pingwing-settings
                                                            'mail)
                                                 'access-server)
                      #:access-port (assoc-ref (assoc-ref pingwing-settings
                                                          'mail)
                                               'access-port)
                      #:from-name (car (string-split (assoc-ref task "sender")
                                                     #\^))
                      #:from-address (cadr (string-split (assoc-ref task
                                                                    "sender")
                                                         #\^))
                      #:to-name (car (string-split recipient #\^))
                      #:to-address (car (string-split recipient #\^))
                      #:subject (assoc-ref task "subject")
                      #:body (assoc-ref task "body")))

(define-public (pingwing-worker-thread pingwing-settings)
  (display (format #f "\n~a...\n"
                   (gettext "initializing pingwing queue worker")))

  (use-modules (pingwing tasks)
               (app models task))

  (while #t
    (let* ((oldest-task-not-done ($task 'get
                                        #:ret 1
                                        #:condition (where #:task_status
                                                           "pending")
                                        #:order-by "created_at ASC")))
      (unless (nil? oldest-task-not-done)
        (catch #t
          (lambda ()
            (display "
================
processing pingwing task
")
            (write oldest-task-not-done)

            (for-each (lambda (recipient)
                        (do-send-mail #:recipient recipient
                                      #:pingwing-settings pingwing-settings
                                      #:task (car oldest-task-not-done)))
                      (string-split (assoc-ref (car
                                                oldest-task-not-done)
                                               "recipients") #\;)))
          (lambda (key . args)
            (display (format #f "\nerror processing task: ~a ~a" key
                             args)))))
      (sleep 3))))

