;;; pingwing -- the free and open Lisp-powered notification nexus

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

(define-module (pingwing templates system-alert)
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
  #:use-module (sxml simple)
  #:use-module (ice-9 iconv))

(begin
  (define* (system-alert-html-template #:key system-name alert-value)
    (let* (
           (tree `((html (head ,meta-charset
                               ,meta-ie
                               ,meta-responsive
                               ,meta-color-scheme
                               ,meta-supported-color-schemes
                               (title ,(gettext "System Alert"))
                               (style ,mail-style))
                         (body (h1 (span ,(gettext
                                           "System Alert: "))
                                   (span ,system-name))
                               (p ,(gettext
                                    "An alert has been triggered from your system"))
                               (hr (@ (style ,(->style '((margin-top . "1.4em") (margin-bottom . "1.4em"))))))
                               (p ,alert-value)
                               ,mail-footer)))))
      (with-output-to-string (lambda ()
                               (sxml->xml tree)))))
  (export system-alert-html-template))

(begin
  (define* (system-alert-plain-template #:key system-name alert-value)
    (let* ((content (list (gettext "System Alert")
                          (gettext
                           "An alert has been triggered from your system:")
                          system-name
                          "----------------------------------"
                          alert-value
                          "----------------------------------"
                          (gettext
                           "this e-mail was powered by pingwing - the free and open Lisp-powered notification nexus")
                          "https://codeberg.org/jjba23/pingwing"
                          (gettext "see pingwing's source code on Codeberg"))))
      (string-join content "\n")))
  (export system-alert-plain-template))
