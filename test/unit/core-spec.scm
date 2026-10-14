;;; pingwing -- the free and open Lisp-powered notification nexus

;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;; pingwing is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Affero General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; pingwing is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Affero General Public License for more details.

;; You should have received a copy of the GNU Affero General Public License
;; along with pingwing.  If not, see <https://www.gnu.org/licenses/>.

;;; The tests that do not need a database or a mail server: the encodings that
;;; keep a message intact on the wire, the shape of the message itself, and the
;;; templates' own promises about what they always say.  This file is loaded by
;;; test/run-tests.scm, which owns the runner.

(use-modules (srfi srfi-64)
             (srfi srfi-1)
             (ice-9 regex)
             (ice-9 format)
             (ice-9 string-fun)
             (pingwing mail)
             (pingwing css)
             (pingwing html)
             (pingwing templates password-reset)
             (pingwing templates system-alert)
             (pingwing templates lucidplan-new-ticket))

(define (contains? haystack needle)
  (and (string? haystack)
       (not (string-null? haystack))
       (string-contains haystack needle)
       #t))

(test-begin "pingwing-core")

(test-group
 "quoted-printable"
 (test-assert "an equals sign is escaped"
              (contains? (quoted-printable-encode "a=b") "a=3Db"))
 (test-assert "a leading dot is escaped so SMTP cannot end DATA early"
              (contains? (quoted-printable-encode ".dot\nnext") "=2Edot"))
 (test-assert "non-ASCII is escaped byte by byte"
              (contains? (quoted-printable-encode "\u00e9") "=C3=A9"))
 (test-assert "lines are split with CRLF"
              (contains? (quoted-printable-encode "one\ntwo") "one\r\ntwo"))
 (test-assert "a trailing space is escaped"
              (contains? (quoted-printable-encode "tail \n") "tail=20")))

(test-group
 "headers"
 (test-assert "ASCII is left readable" (equal? (rfc2047-encode "hello") "hello"))
 (test-assert "non-ASCII is encoded"
              (contains? (rfc2047-encode "\u00e9") "=?UTF-8?B?"))
 (test-assert "a line break cannot inject a header"
              (not (contains? (sanitize-header "a\r\nBcc: x") "\n")))
 (test-assert "a display name with a comma is quoted"
              (contains? (format-address "Doe, Jane" "j@x.y") "\"Doe, Jane\" <j@x.y>"))
 (test-assert "a bare address carries no angle brackets"
              (equal? (format-address "" "j@x.y") "j@x.y"))
 (test-assert "the date is an RFC 5322 date"
              (let ((d (rfc5322-date)))
                (and (regexp-exec
                      (make-regexp
                       "^[A-Z][a-z][a-z], [0-9][0-9] [A-Z][a-z][a-z] [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}$")
                      d)
                     #t))))

(test-group
 "the message"
 (let ((m (build-mail-message #:id "the-id"
                              #:from-name "No Reply"
                              #:from-address "n@x.y"
                              #:to-name "Joe"
                              #:to-address "j@x.y"
                              #:subject "Hi"
                              #:body "plain body"
                              #:body-html "<p>html body</p>")))
   (test-assert "the id is appended to the subject"
                (contains? m "Subject: Hi the-id"))
   (test-assert "a Message-ID is generated" (contains? m "Message-ID: <"))
   (test-assert "a Date header is present" (contains? m "Date: "))
   (test-assert "both parts are present"
                (and (contains? m "plain body")
                     (contains? m "html body")))
   (test-assert "the boundary opens and closes"
                (and (contains? m "multipart/alternative; boundary=\"")
                     (contains? m "--pingwing-")))
   (test-assert "every line ends CRLF (no bare LF)"
                (not (string-any (lambda (c) (char=? c #\newline))
                                 (string-replace-substring m "\r\n" ""))))))

(test-group
 "password reset template"
 (let ((html (password-reset-html-template #:system-name "WikiMusic"
                                           #:user "joe@x.y"
                                           #:reset-link "https://x/y")))
   (test-assert "the account is named" (contains? html "joe@x.y"))
   (test-assert "the link is present" (contains? html "https://x/y"))
   (test-assert "the style is inline" (contains? html "style="))
   (test-assert "the frosted panel is there" (contains? html "pw-panel"))))

(test-group
 "system alert template"
 (let ((html (system-alert-html-template #:system-name "X"
                                         #:alert-value "disk full")))
   (test-assert "the alert is shown" (contains? html "disk full"))
   (test-assert "the system is named" (contains? html "X"))))

(test-group
 "lucidplan new-ticket template"
 (let ((html (lucidplan-new-ticket-html-template
              #:system-name "Lucidplan"
              #:project-name "Pingwing"
              #:ticket-human-id 12
              #:ticket-title "Fix the SMTP retry"
              #:ticket-type "bug"
              #:priority 2
              #:author "joe"
              #:ticket-url "https://lucidplan/x/ticket/12"))
       (plain (lucidplan-new-ticket-plain-template
               #:system-name "Lucidplan"
               #:project-name "Pingwing"
               #:ticket-human-id 12
               #:ticket-title "Fix the SMTP retry"
               #:ticket-url "https://lucidplan/x/ticket/12")))
   (test-assert "the project is named" (contains? html "Pingwing"))
   (test-assert "the ticket number is shown as #12" (contains? html "#12"))
   (test-assert "the title is shown" (contains? html "Fix the SMTP retry"))
   (test-assert "the link is shown" (contains? html "https://lucidplan/x/ticket/12"))
   (test-assert "the plain part names the ticket too"
                (contains? plain "Fix the SMTP retry"))
   (test-assert "the plain part names the project"
                (contains? plain "Pingwing"))))

(test-group
 "the fonts and the glass"
 (let ((head (mail-head-style)))
   (test-assert "Lucida is declared" (contains? head "Lucida Sans"))
   (test-assert "Intel One Mono is asked for" (contains? head "Intel+One+Mono"))
   (test-assert "the dark theme is offered" (contains? head "prefers-color-scheme"))
   (test-assert "the panel declares a frost blur"
                (contains? (password-reset-html-template #:system-name "X"
                                                         #:user "u@x.y"
                                                         #:reset-link "https://x/y")
                           "backdrop-filter"))))

(test-end "pingwing-core")
