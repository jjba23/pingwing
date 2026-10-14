;;; pingwing -- The free and open Lisp-powered notification nexus

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

;;; The templates' own promises about what they always say: a reader is named,
;;; the thing the mail is about is named, and the link is one a click can
;;; follow.  The styling is checked in the same place, since it is what a
;;; message looks like when it arrives -- one style block, inline, with the
;;; frosted panel the family's mails share.

(define-module (veritas unit templates-spec)
  #:use-module (veritas veritas)
  #:use-module (ice-9 format)
  #:use-module (pingwing css)
  #:use-module (pingwing templates password-reset)
  #:use-module (pingwing templates system-alert)
  #:use-module (pingwing templates lucidplan-new-ticket)
  #:export (spec))

;;; ====== password reset ======

(define password-reset-suite
  (let ((html (password-reset-html-template #:system-name "WikiMusic"
                                            #:user "joe@x.y"
                                            #:reset-link "https://x/y")))
    (suite
     "password reset template"
     (test "the account is named"
           (assert-contains #:name "the reader is told whose account this is"
                            #:expect html
                            #:got "joe@x.y"))
     (test "the link is present"
           (assert-contains #:name "the reset link is in the mail"
                            #:expect html
                            #:got "https://x/y"))
     (test "the style is inline"
           (assert-contains #:name "a mail client that drops stylesheets still sees it"
                            #:expect html
                            #:got "style="))
     (test "the frosted panel is there"
           (assert-contains #:name "the panel the family's mails share is drawn"
                            #:expect html
                            #:got "pw-panel")))))

;;; ====== system alert ======

(define system-alert-suite
  (let ((html (system-alert-html-template #:system-name "X"
                                          #:alert-value "disk full")))
    (suite
     "system alert template"
     (test "the alert is shown"
           (assert-contains #:name "what went wrong is in the mail"
                            #:expect html
                            #:got "disk full"))
     (test "the system is named"
           (assert-contains #:name "which system raised it is in the mail"
                            #:expect html
                            #:got "X")))))

;;; ====== lucidplan, new ticket ======

(define new-ticket-suite
  (let* ((html (lucidplan-new-ticket-html-template
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
    (suite
     "lucidplan new-ticket template"
     (test "the HTML part names the project, the ticket and the link"
           (assert-contains #:name "the project is named"
                            #:expect html
                            #:got "Pingwing")
           (assert-contains #:name "the ticket number reads as #12"
                            #:expect html
                            #:got "#12")
           (assert-contains #:name "the title is shown"
                            #:expect html
                            #:got "Fix the SMTP retry")
           (assert-contains #:name "the link is shown"
                            #:expect html
                            #:got "https://lucidplan/x/ticket/12"))
     (test "the plain part says the same thing"
           (assert-contains #:name "the plain part names the ticket too"
                            #:expect plain
                            #:got "Fix the SMTP retry")
           (assert-contains #:name "the plain part names the project"
                            #:expect plain
                            #:got "Pingwing")))))

;;; ====== the look ======

(define styling-suite
  (let ((head (mail-head-style)))
    (suite
     "the fonts and the glass"
     (test "the faces are declared"
           (assert-contains #:name "Lucida is declared"
                            #:expect head
                            #:got "Lucida Sans")
           (assert-contains #:name "Intel One Mono is asked for"
                            #:expect head
                            #:got "Intel+One+Mono"))
     (test "both colour schemes are offered"
           (assert-contains #:name "a dark theme is offered"
                            #:expect head
                            #:got "prefers-color-scheme"))
     (test "the panel declares a frost blur"
           (assert-contains
            #:name "the panel is frosted, not merely translucent"
            #:expect (password-reset-html-template #:system-name "X"
                                                   #:user "u@x.y"
                                                   #:reset-link "https://x/y")
            #:got "backdrop-filter")))))

(define (spec)
  (veritas-run password-reset-suite
               system-alert-suite
               new-ticket-suite
               styling-suite))
