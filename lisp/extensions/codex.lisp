;;;; codex.lisp -- a stub for OpenAI's Codex, next to Claude
;;;;
;;;;   C-c x   ask Codex (same question window as C-c r)
;;;;
;;;; Everything around the call -- the question prompt, the buffer context,
;;;; the answer window, C-c y to insert proposed code -- is shared with
;;;; Claude (see assistant.lisp).  Only CODEX-ASK is missing: it must take
;;;; the question and the context and return the answer as a string.
;;;;
;;;; Two likely ways to fill it in:
;;;;
;;;;   * the Codex CLI in non-interactive mode, `codex exec`
;;;;     (developers.openai.com/codex/noninteractive), run with
;;;;     RUN-WITH-INPUT exactly as CLAUDE-CLI-ASK runs `claude -p`;
;;;;     keep it read-only (the First Law) with its sandbox settings;
;;;;   * the OpenAI Responses API through curl, as CLAUDE-API-ASK does
;;;;     for the Messages API, with OPENAI_API_KEY.

(in-package #:sbemacs)

(defvar *codex-program* "codex"
  "The Codex CLI, for when the stub is filled in.")

(defun codex-ask (question context)
  (declare (ignore question context))
  (format nil "The Codex assistant is a stub: nothing was sent.~%~%~
               To make it work, fill in CODEX-ASK in lisp/extensions/codex.lisp~%~
               (~:[the codex program was not found on the PATH~;~:*found ~A~]).~%~
               C-x C-r reloads the script afterwards; no rebuild needed."
          (let ((p (find-program *codex-program*))) (and p (native p)))))

(define-assistant :codex "Codex" 'codex-ask)

(defun ask-codex () (ask-assistant :codex))

(global-set-key "C-c x" 'ask-codex)
