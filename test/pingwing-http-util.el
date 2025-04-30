;;; pingwing-http-util.el --- P4 HTTP calls helper -*- lexical-binding: t -*-

;; Package-Requires: ((request "0.3.3"))

;; Local Variables:
;; byte-compile-warnings: (not free-vars unresolved)
;; End:

;;; Commentary:

;; Using Emacs and request.el we can make our life easier and execute HTTP requests directly from Emacs
;; and post or pre-process data easily

;;; Code:

(defun pingwing-get-tasks ()
  "Get tasks in pingwing."
  (let* ((host "http://localhost:50077"))
    (request (string-join `(,host
                            "/api/v1/tasks"))
      :success (cl-function
                (lambda (&key response &allow-other-keys)
                  (message "Done: %s" (request-response-status-code response))
                  (sss-new-buffer-with-json (format "pingwing-http-util-%s" (sss-uuidgen-string))
                                            (request-response-data response))))
      :error (cl-function (lambda (&key error &allow-other-keys)
                            (message "Error: %s" error))))))

;;(pingwing-get-tasks)

(setq pingwing-reset-password-mail '((task-type . send-email)
                                     (template . password-reset)
                                     (template-vars . ((system-name . WikiMusic)
                                                       (user . "jjbigorra@gmail.com")
                                                       (reset-link . "https://gnu.org")))
                                     (sender-name . "No Reply - WikiMusic")
                                     (sender-address . "noreply@wikimusic.jointhefreeworld.org")
                                     (subject . "WikiMusic - Password Reset")
                                     (recipients . (((name . "Josep Bigorra")(address . "jjbigorra@gmail.com"))))))

(setq pingwing-system-alert-mail '((task-type . send-email)
                                   (template . system-alert)
                                   (template-vars . ((system-name . Oculuslambda)
                                                     (alert-value . "CPU utilization exceeded the threshold of 80%")
                                                     ))
                                   (sender-name . "No Reply - Oculuslambda")
                                   (sender-address . "noreply@oculuslambda.jointhefreeworld.org")
                                   (subject . "Oculuslambda - CPU usage")
                                   (recipients . (((name . "Josep Bigorra")(address . "jjbigorra@gmail.com"))))))

(defun pingwing-create-task (data)
  "Create a simple task in pingwing."
  (let* ((host "http://localhost:50077"))
    (request (string-join `(,host
                            "/api/v1/tasks"))
      :type "POST"
      :data (json-encode data)
      :headers '(("Content-Type" . "application/json"))
      :parser 'json-read
      :success (cl-function
                (lambda (&key response &allow-other-keys)
                  (message "Done: %s" (request-response-status-code response))
                  (sss-new-buffer-with-json (format "pingwing-http-util-%s" (sss-uuidgen-string))
                                            (json-encode (request-response-data response)))))
      :error (cl-function (lambda (&key error &allow-other-keys)
                            (message "Error: %s" error))))))

;;(pingwing-create-task pingwing-reset-password-mail)
;;(pingwing-create-task pingwing-system-alert-mail)


(provide 'pingwing-http-util)

;;; pingwing-http-util.el ends here
