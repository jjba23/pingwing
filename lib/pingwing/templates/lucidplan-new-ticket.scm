;; pingwing - the free and open Lisp-powered notification nexus
;;
;; SPDX-License-Identifier: MIT
;; Copyright © Josep Bigorra <jjbigorra@gmail.com>

;;; Told to the people of a lucidplan project when a ticket joins it.  The
;;; template is written to be sent to anyone -- the reporter, the assignee, a
;;; watcher -- so it names the project, the ticket and who opened it, and it
;;; says plainly that reading it asks no action.  Every fact past the title is
;;; optional: a lucidplan that knows less than usual still gets a message that
;;; does not read as broken.

(define-module (pingwing templates lucidplan-new-ticket)
  #:use-module (ice-9 time)
  #:use-module (ice-9 format)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 regex)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-64)
  #:use-module (pingwing css)
  #:use-module (pingwing html)
  #:use-module (ice-9 string-fun)
  #:use-module (ice-9 iconv)
  #:export (lucidplan-new-ticket-html-template
            lucidplan-new-ticket-plain-template))

;; A ticket number is a bare integer in lucidplan's own URL, but it reads as a
;; number only when it is set off by a '#'; either way it is turned into text
;; here so a template handed a number and one handed a string agree.
(define (ticket-number human-id)
  (cond
    ((or (not human-id)
         (equal? human-id ""))
     #f)
    ((number? human-id)
     (format #f "#~a" human-id))
    ((string-prefix? "#" human-id)
     human-id)
    (else (format #f "#~a" human-id))))

;; "set" here means a value worth putting in a fact row: not #f and not the
;; empty string, which is what an optional field arrives as.
(define (set-value v)
  (cond
    ((not v)
     #f)
    ((and (string? v)
          (string-null? v))
     #f)
    (else (format #f "~a" v))))

(define* (lucidplan-new-ticket-html-template #:key system-name
                                             project-name
                                             project-human-id
                                             ticket-human-id
                                             ticket-title
                                             ticket-type
                                             ticket-status
                                             priority
                                             author
                                             assignee
                                             description
                                             ticket-url)
  (let* ((project (or (set-value project-name)
                      (set-value project-human-id)
                      (gettext "your project")))
         (number (ticket-number ticket-human-id))
         (opener (or (set-value author)
                     (gettext "someone")))
         (described? (set-value description))
         (tree (mail-document #:title (format #f "~a ~a"
                                              (gettext "New ticket in")
                                              project)
                              #:content `((h1 (@ (class . "pw-heading")
                                                 (style ,(mail-heading-style)))
                                              ,(format #f "~a ~a"
                                                       (gettext
                                                        "New ticket in")
                                                       project))
                                          (p (@ (class . "pw-text")
                                                (style ,(mail-text-style)))
                                             ,(format #f
                                                      (gettext
                                                       "~a opened a new ticket~a. Here is what it says.")
                                                      opener
                                                      (if number
                                                          (format #f " ~a"
                                                                  number) "")))
                                          ,(mail-inner (list (mail-facts (list
                                                                          (cons
                                                                           (gettext
                                                                            "Ticket")
                                                                           (and
                                                                            number
                                                                            (mail-mono
                                                                             number)))
                                                                          (cons
                                                                           (gettext
                                                                            "Title")
                                                                           (set-value
                                                                            ticket-title))
                                                                          (cons
                                                                           (gettext
                                                                            "Project")
                                                                           (mail-mono
                                                                            project))
                                                                          (cons
                                                                           (gettext
                                                                            "Type")
                                                                           (set-value
                                                                            ticket-type))
                                                                          (cons
                                                                           (gettext
                                                                            "Priority")
                                                                           (set-value
                                                                            priority))
                                                                          (cons
                                                                           (gettext
                                                                            "Status")
                                                                           (set-value
                                                                            ticket-status))
                                                                          (cons
                                                                           (gettext
                                                                            "Assignee")
                                                                           (set-value
                                                                            assignee))))))
                                          ,@(if described?
                                                `((p (@ (class . "pw-muted")
                                                        (style ,(mail-muted-style)))
                                                     ,(gettext "Description"))
                                                  ,(mail-inner (list `(div (@ (style
                                                                               "white-space:pre-wrap;word-break:break-word;"))
                                                                           ,description))))
                                                '())
                                          ,(mail-button #:href (or (set-value
                                                                    ticket-url)
                                                                   "#")
                                                        #:label (format #f
                                                                 "~a ~a"
                                                                 (gettext
                                                                  "Open ticket on")
                                                                 (or (set-value
                                                                      system-name)
                                                                     (gettext
                                                                      "your board"))))
                                          (p (@ (class . "pw-muted")
                                                (style ,(mail-muted-style)))
                                             ,(gettext
                                               "If the button does not work, copy and paste this link into your browser:"))
                                          (p (@ (class . "pw-mono")
                                                (style ,(mail-mono-style)))
                                             ,(or (set-value ticket-url) ""))
                                          ,(mail-rule)
                                          (p (@ (class . "pw-muted")
                                                (style ,(mail-muted-style)))
                                             ,(gettext
                                               "You receive this because you take part in this project; no action is needed to keep receiving them.")))))
         (_ tree))
    (mail-document->string tree)))

(define* (lucidplan-new-ticket-plain-template #:key system-name
                                              project-name
                                              project-human-id
                                              ticket-human-id
                                              ticket-title
                                              ticket-type
                                              ticket-status
                                              priority
                                              author
                                              assignee
                                              description
                                              ticket-url)
  (let* ((project (or (set-value project-name)
                      (set-value project-human-id)
                      (gettext "your project")))
         (number (ticket-number ticket-human-id))
         (opener (or (set-value author)
                     (gettext "someone")))
         (content (append (list (format #f "~a ~a"
                                        (gettext "New ticket in") project) ""
                                (format #f
                                        (gettext "~a opened a new ticket~a.")
                                        opener
                                        (if number
                                            (format #f " ~a" number) "")) "")
                          (if number
                              (list (format #f "~a ~a"
                                            (gettext "Ticket:") number))
                              '())
                          (if (set-value ticket-title)
                              (list (format #f "~a ~a"
                                            (gettext "Title:") ticket-title))
                              '())
                          (list (format #f "~a ~a"
                                        (gettext "Project:") project))
                          (if (set-value ticket-type)
                              (list (format #f "~a ~a"
                                            (gettext "Type:") ticket-type))
                              '())
                          (if (set-value priority)
                              (list (format #f "~a ~a"
                                            (gettext "Priority:") priority))
                              '())
                          (if (set-value ticket-status)
                              (list (format #f "~a ~a"
                                            (gettext "Status:") ticket-status))
                              '())
                          (if (set-value assignee)
                              (list (format #f "~a ~a"
                                            (gettext "Assignee:") assignee))
                              '())
                          (if (set-value description)
                              (list ""
                                    (gettext "Description:") description)
                              '())
                          (list ""
                                (format #f "~a: ~a"
                                        (gettext "Open the ticket")
                                        (or (set-value ticket-url) ""))
                                "----------------------------------"
                                (format #f "~a ~a"
                                        (gettext "this message was sent by")
                                        (or (set-value system-name)
                                            "lucidplan"))
                                (gettext
                                 "this e-mail was powered by pingwing - the free and open Lisp-powered notification nexus")
                                "https://codeberg.org/jjba23/pingwing"
                                (gettext
                                 "see pingwing's source code on Codeberg")))))
    (string-join content "\n")))
