;;; lucidplan - the CI/CD orchestrator written in Guile Scheme

;; Copyright © 2025 "Josep Bigorra" known as "jjba23" <jjbigorra@gmail.com>

;; lucidplan is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; lucidplan is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with lucidplan.  If not, see <https://www.gnu.org/licenses/>.

(use-modules (ice-9 rdelim))
(use-modules (srfi srfi-64))
(use-modules (hygguile abstraction))

(define (run-test file)
  (display "Running: ")
  (display file)
  (newline)
  (primitive-load file))

(define (run-all-tests)
  (for-each run-test
            '("lib/lucidplan/prelude.scm")))

(run-all-tests)
