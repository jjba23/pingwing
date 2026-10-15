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

;;; The encodings that keep a message intact on the wire, and the shape of the
;;; message itself.  Nothing here touches a database or a mail server: what is
;;; checked is what pingwing promises about the bytes it hands to one.
;;;
;;; The module is named `(veritas unit mail-spec)' because that is the name the
;;; veritas runner derives from where the file sits (test/veritas/unit), which
;;; is how `maak test' loads it.

(define-module (veritas unit mail-spec)
  #:use-module (veritas veritas)
  #:use-module (ice-9 string-fun)
  #:use-module (pingwing mail)
  #:export (spec))

;;; ====== quoted-printable ======
;;;
;;; The body is quoted-printable like the RFC asks: an `=' is what introduces
;;; an escape, a line may not carry a bare newline (the wire wants CRLF), and a
;;; space or dot at the end of a line must not be one SMTP can eat.

(define quoted-printable-suite
  (suite "quoted-printable"
         (test "an equals sign is escaped"
               (assert-contains #:name "the escape character escapes itself"
                                #:expect (quoted-printable-encode "a=b")
                                #:got "a=3Db"))
         (test "a leading dot is escaped so SMTP cannot end DATA early"
               (assert-contains #:name
                                "a line that starts with a dot is encoded"
                                #:expect (quoted-printable-encode ".dot\nnext")
                                #:got "=2Edot"))
         (test "non-ASCII is escaped byte by byte"
               (assert-contains #:name
                                "an accented character travels as its bytes"
                                #:expect (quoted-printable-encode "é")
                                #:got "=C3=A9"))
         (test "lines are split with CRLF"
               (assert-contains #:name "a newline becomes CRLF"
                                #:expect (quoted-printable-encode "one\ntwo")
                                #:got "one\r\ntwo"))
         (test "a trailing space is escaped"
               (assert-contains #:name
                                "a space before a newline cannot be eaten"
                                #:expect (quoted-printable-encode "tail \n")
                                #:got "tail=20"))))

;;; ====== headers ======

(define headers-suite
  (suite "headers"
         (test "ASCII is left readable"
               (assert-equal #:name
                             "nothing is encoded that needs no encoding"
                             #:expect "hello"
                             #:got (rfc2047-encode "hello")))
         (test "non-ASCII is encoded"
               (assert-contains #:name "an accented subject is base64 encoded"
                                #:expect (rfc2047-encode "é")
                                #:got "=?UTF-8?B?"))
         (test "a line break cannot inject a header"
               (assert-not-contains #:name
                "a CRLF in a value cannot open a header of its own"
                #:expect (sanitize-header "a\r\nBcc: x")
                #:got "\n"))
         (test "a display name with a comma is quoted"
               (assert-contains #:name "a comma in a display name is quoted"
                                #:expect (format-address "Doe, Jane" "j@x.y")
                                #:got "\"Doe, Jane\" <j@x.y>"))
         (test "a bare address carries no angle brackets"
               (assert-equal #:name
                             "an address with no name is just the address"
                             #:expect "j@x.y"
                             #:got (format-address "" "j@x.y")))
         (test "the date is an RFC 5322 date"
               (assert-matches #:name
                "the date header is the shape a mail server reads"
                #:pattern
                "^[A-Z][a-z][a-z], [0-9][0-9] [A-Z][a-z][a-z] [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}$"
                #:got (rfc5322-date)))))

;;; ====== the message ======

(define (occurrences needle haystack)
  "How many times NEEDLE appears in HAYSTACK."
  (let loop
    ((from 0)
     (seen 0))
    (let ((at (string-contains haystack needle from)))
      (if at
          (loop (+ at
                   (string-length needle))
                (+ seen 1)) seen))))

(define message-suite
  (let ((m (build-mail-message #:id "the-id"
                               #:from-name "No Reply"
                               #:from-address "n@x.y"
                               #:to-name "Joe"
                               #:to-address "j@x.y"
                               #:subject "Hi"
                               #:body "plain body"
                               #:body-html "<p>html body</p>")))
    (suite "the message"
           (test "the id is appended to the subject"
                 (assert-contains #:name
                                  "a reader can match the mail to the task"
                                  #:expect m
                                  #:got "Subject: Hi the-id"))
           (test "a Message-ID is generated"
                 (assert-contains #:name
                                  "the message carries an id of its own"
                                  #:expect m
                                  #:got "Message-ID: <"))
           (test "a Date header is present"
                 (assert-contains #:name "the message is dated"
                                  #:expect m
                                  #:got "Date: "))
           (test "both parts are present"
                 (assert-true (and (string-contains m "plain body")
                                   (string-contains m "html body") #t)
                              #:name
                              "the plain and the HTML body are both there"))
           (test "the boundary opens and closes"
                 (assert-true (and (string-contains m
                                    "multipart/alternative; boundary=\"")
                                   (string-contains m "--pingwing-") #t)
                              #:name
                              "a multipart message declares its boundary"))
           (test "every line ends CRLF (no bare LF)"
                 (assert-false (string-any (lambda (c)
                                             (char=? c #\newline))
                                           (string-replace-substring m "\r\n"
                                                                     ""))
                               #:name
                               "no bare newline survives into the message"))
           ;; A message that reaches a client without a doctype is read as
           ;; legacy HTML -- quirks mode -- where the widths and the table box
           ;; a mail is laid out with are not the ones its styles ask for.  The
           ;; doctype belongs to the document, which writes it where it is
           ;; built (`mail-document->string'), so this assembler says nothing
           ;; about it: a second one is not a document, and one invented here
           ;; would be a doctype the document never wrote.  That the document's
           ;; own reaches a client is asserted where a document is at hand --
           ;; `templates-spec', over the messages a template produces.
           (test "the HTML part is carried through as the caller wrote it"
                 (assert-contains #:name "the body's own markup survives"
                                  #:expect m
                                  #:got "<p>html body</p>")
                 (assert-equal #:name "no doctype is invented here"
                               #:expect 0
                               #:got (occurrences "<!DOCTYPE" m))))))

(define (spec)
  (veritas-run quoted-printable-suite headers-suite message-suite))
