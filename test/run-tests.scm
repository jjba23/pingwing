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

;;; The test entry point `maak test' runs.  It owns the SRFI-64 runner, loads
;;; every spec under test/unit, and leaves with a non-zero status when anything
;;; failed, so a build step can trust the exit code.

(use-modules (srfi srfi-64)
             (ice-9 format))

(define runner (test-runner-simple))
(test-runner-current runner)

;; Loaded by absolute path rather than `include'd, so that a spec edited
;; between two runs is genuinely re-read instead of served from the compiled
;; copy of this file.
(load (string-append (getcwd) "/test/unit/core-spec.scm"))

(let ((passed (test-runner-pass-count runner))
      (failed (test-runner-fail-count runner)))
  (format #t "\n~a passed, ~a failed\n" passed failed)
  (exit (if (zero? failed) 0 1)))
