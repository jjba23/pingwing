;;; pingwing -- The free and open Lisp-powered notification nexus

;; Copyright © Josep Bigorra known as "jjba23" <jjbigorra@gmail.com>

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

(define-module (pingwing domain repo)
  #:declarative? #t
  #:use-module (srfi srfi-9)
  #:export (define-repo-method define-record-with-kw))

(define-syntax define-repo-method
  (syntax-rules ()
                ((_ method-name accessor docstring)
                 (define* (method-name repo . args)
                   docstring
                   (apply (accessor repo) args)))))

(define-syntax define-record-with-kw
  (syntax-rules ()
                ((_ (type-name constructor-name pred) kw-constructor-name
                    (field-name accessor-name) ...)
                 (begin
                   ;; Define the standard SRFI-9 record
                   (define-record-type type-name
                     (constructor-name field-name ...) pred
                     (field-name accessor-name) ...)

                   ;; Define the keyword-argument constructor
                   (define* (kw-constructor-name #:key field-name ...)
                     (constructor-name field-name ...))

                   ;; Auto-export members
                   (export type-name pred kw-constructor-name accessor-name
                           ...)))))
