;;; align.lisp
;;; Classes, generic functions, methods and functions for aligning
;;; biological sequences
;;;
;;; Copyright (c) 2002-2018 Cyrus Harmon (ch-lisp@bobobeach.com)
;;; All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;;
;;;   * Redistributions of source code must retain the above copyright
;;;     notice, this list of conditions and the following disclaimer.
;;;
;;;   * Redistributions in binary form must reproduce the above
;;;     copyright notice, this list of conditions and the following
;;;     disclaimer in the documentation and/or other materials
;;;     provided with the distribution.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR 'AS IS' AND ANY EXPRESSED
;;; OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
;;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
;;; DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
;;; GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;

(in-package :bio-align)

(defgeneric global-align-aa (seq1 seq2))
(defgeneric global-align-na (seq1 seq2 &key gap gap-extend match mismatch transition terminal-gap terminal-gap-extend))
(defgeneric global-align-aa-affine-gaps (seq1 seq2 &key gap gap-extend terminal-gap terminal-gap-extend))
(defgeneric global-align-na-affine-gaps (seq1 seq2 &key gap gap-extend match mismatch
                                              transition terminal-gap terminal-gap-extend))
(defgeneric local-align-aa (seq1 seq2))
(defgeneric local-align-na (seq1 seq2 &key gap match mismatch))
(defgeneric local-align-aa-affine-gaps (seq1 seq2))
(defgeneric local-align-na-affine-gaps (seq1 seq2))

;;
;; alignment objects are used to store information about a pairwise
;; alignment, e.g. the two sequences being aligned, the dynamic
;; programming matrix, three matrices used in computing the alignment,
;; and the matrix used to store the traceback.
(defclass alignment ()
  ((score :accessor alignment-score :initarg :score)
   (seq1 :accessor alignment-seq1 :initarg :seq1)
   (seq2 :accessor alignment-seq2 :initarg :seq2)
   (dp-matrix :accessor alignment-dp-matrix :initarg :dp-matrix)
   (dp-down-matrix :accessor alignment-dp-down-matrix :initarg :dp-down-matrix :initform nil)
   (dp-right-matrix :accessor alignment-dp-right-matrix :initarg :dp-right-matrix :initform nil)
   (dp-traceback :accessor alignment-dp-traceback :initarg :dp-traceback)))

(defclass local-alignment (alignment)
  ((ungapped-seq1 :accessor alignment-ungapped-seq1 :initarg :ungapped-seq1)
   (ungapped-seq2 :accessor alignment-ungapped-seq2 :initarg :ungapped-seq2)))

(defun make-alignment (&rest args &key score seq1 seq2 dp-matrix dp-down-matrix dp-right-matrix dp-traceback (class 'alignment))
  (declare (ignorable score seq1 seq2 dp-matrix dp-down-matrix dp-right-matrix dp-traceback))
  (apply #'make-instance class
         (alexandria:remove-from-plist args :class)))

(defun make-local-alignment (&rest args &key score seq1 seq2 ungapped-seq1 ungapped-seq2
                                             dp-matrix dp-down-matrix dp-right-matrix dp-traceback (class 'local-alignment))
  (declare (ignorable score seq1 seq2 ungapped-seq1 ungapped-seq2  dp-matrix dp-down-matrix dp-right-matrix dp-traceback))
  (apply #'make-instance class
         (alexandria:remove-from-plist args :class)))

(defun alignment-results (a)
  (values (alignment-score a)
          (alignment-seq1 a)
          (alignment-seq2 a)))

(defun print-alignment-matrices (a)
  (print (alignment-dp-matrix a))
  (unless (null (alignment-dp-down-matrix a))
    (print (alignment-dp-down-matrix a)))
  (unless (null (alignment-dp-right-matrix a))
    (print (alignment-dp-right-matrix a)))
  (print (alignment-dp-traceback a)))

;;
;; score-matrix objects describe various scoring matrices,
;; e.g. BLOSUM62, PAM matrices, etc...
(defclass score-matrix ()
  ((list :accessor score-matrix-list :initarg :list)
   (char-hash :accessor score-matrix-char-hash :initarg :char-hash)
   (scores :accessor score-matrix-scores :initarg :scores)))

(defun make-score-matrix (&key list char-hash scores)
  (apply #'make-instance 'score-matrix
         (append
          (when list `(:list ,list))
          (when char-hash `(:char-hash ,char-hash))
          (when scores `(:scores ,scores)))))

(defun parse-matrix (input-matrix)
  (let ((m (make-score-matrix
            :char-hash (make-hash-table :test #'equal)
            :scores (make-hash-table :test #'equal))))
    (let ((aa-list (first input-matrix)) (i 0))
      (setf (score-matrix-list m) (make-array (list (length input-matrix)) :initial-element 0))
      (dolist (symbol aa-list)
        (let ((c (aref (string symbol) 0))) 
          (setf (aref (score-matrix-list m) i) c)
          (setf (gethash c (score-matrix-char-hash m)) i)
          (incf i))))
    (let ((i 0) (j 0))
      (dolist (l (rest input-matrix))
        (dolist (c l)
          (setf (gethash (list i j) (score-matrix-scores m)) c)
          (incf j))
        (setf j 0)
        (incf i)))
    m))

;;
;; FIXME: this should be memoized!
(defun get-score (m k l)  
  (gethash (list (gethash k (score-matrix-char-hash m)) (gethash l (score-matrix-char-hash m)))
           (score-matrix-scores m)))

(defparameter *blosum-62*
  (parse-matrix
   (with-open-file
       (matrix
        (asdf:component-pathname
         (reduce #'asdf:find-component
                 (list nil "cl-bio-align" "align" "matrix" "blosum62"))))
     (read matrix))))

(defun aa-score (k l &key (scoring-matrix *blosum-62*))
  (get-score scoring-matrix k l))

(defparameter transition-table (make-hash-table :test #'equal))
(setf (gethash #\A transition-table) #\G
      (gethash #\C transition-table) #\T
      (gethash #\G transition-table) #\A
      (gethash #\T transition-table) #\C)

(defun transition (residue)
  (let ((c (gethash (char-upcase residue) transition-table)))
    (if (null c) #\N c)))

(defparameter +gap-char+ #\-)
(declaim (type base-char +gap-char+))

(defparameter *gap* -8)
(defparameter *terminal-gap* 0)
(defparameter *gap-extend* -2)
(defparameter *terminal-gap-extend* 0)
(defparameter *match* 4)
(defparameter *mismatch* -4)
(defparameter *transition* nil)

(declaim (type (signed-byte 8) *gap* *gap-extend* *match* *mismatch*))
(declaim (type (or null (signed-byte 8)) *transition* *terminal-gap* *terminal-gap-extend*))

(defun na-score (k l)
  (declare (type base-char k l)
           (optimize (speed 3) (safety 0)))
  (cond
    ((eql k l) *match*)
    ((eql k +gap-char+) *gap*)
    ((eql l +gap-char+) *gap*)
    ((and *transition*
          (eql (transition k) l)) *transition*)
    (t *mismatch*)))
(declaim (ftype (function (base-char base-char)
                          (signed-byte 8))
                na-score))


(defun gap-score (g i j)
  (if (= 0 (aref g i j))
      *gap*
      *gap-extend*))

(defconstant +match+ 0)
(defconstant +up+ 1)
(defconstant +left+ 2)
(defconstant +terminate+ 3)

(defun emit-global (m n i j a b &optional s1 s2)
  (cond
    ((or (and (= i 0) (= j 0)) (= (aref n i j) +terminate+))
     (list s1 s2))
    ((or (= i 0) (= (aref n i j) +left+))
     (emit-global m n i (1- j) a b
           (cons #\- s1) (cons (aref b (1- j)) s2)))
    ((or (= j 0) (= (aref n i j) +up+))
     (emit-global m n (1- i) j a b
           (cons (aref a (1- i)) s1) (cons #\- s2)))
    (t
     (emit-global m n (1- i) (1- j) a b
           (cons (aref a (1- i)) s1) (cons (aref b (1- j)) s2)))))

(defun global-align-score (m n i j k l score-fn)
  (cond
    ((and (> i 0) (= j 0))
     (let ((y (+ (aref m (1- i) j) (apply score-fn (list k +gap-char+)))))
       (setf (aref m i j) y) (setf (aref n i j) +up+)))
    ((and (= i 0) (> j 0))       
     (let ((z (+ (aref m i (1- j)) (apply score-fn (list +gap-char+ l)))))
       (setf (aref m i j) z) (setf (aref n i j) +left+)))
    (t
     (let ((x (+ (aref m (1- i) (1- j)) (apply score-fn (list k l))))
           (y (+ (aref m (1- i) j) (apply score-fn (list k +gap-char+))))
           (z (+ (aref m i (1- j)) (apply score-fn (list +gap-char+ l)))))
       (cond
         ((and (>= x y) (>= x z))
          (setf (aref m i j) x
                (aref n i j) +match+))
         ((>= y z)
          (setf (aref m i j) y
                (aref n i j) +up+))
         (t
          (setf (aref m i j) z
                (aref n i j) +left+)))))))

(defun global-align-score-affine-gaps (m n d r i j k l score-fn)
  (cond
    ((and (> i 0) (= j 0))
     (let ((y (max (+ (aref d (- i 1) j) (if (> i 1) *terminal-gap-extend* *terminal-gap*))
                   (+ (aref m (- i 1) j) (apply score-fn (list k +gap-char+))))))
       (setf (aref m i j) y)
       (setf (aref n i j) +up+)
       (setf (aref d i j) y)
       (setf (aref r i j)
             (+ (aref r (- i 1) j) *terminal-gap*))))
    ((and (= i 0) (> j 0))
     (let ((z (max (+ (aref r i (- j 1))  (if (> j 1) *terminal-gap-extend* *terminal-gap*))
                   (+ (aref m i (- j 1)) (apply score-fn (list +gap-char+ l))))))
       (setf (aref m i j) z)
       (setf (aref n i j) +left+)
       (setf (aref r i j) z)
       (setf (aref d i j)
             (+ (aref d i (- j 1)) *terminal-gap*))))
    (t
     (let ((x (+ (aref m (1- i) (1- j)) (apply score-fn (list k l))))
           (y (max (+ (aref d (1- i) j) *gap-extend*)
                   (+ (aref m (1- i) j) (apply score-fn (list k +gap-char+)))))
           (z (max (+ (aref r i (1- j)) *gap-extend*)
                   (+ (aref m i (1- j)) (apply score-fn (list +gap-char+ l))))))
       (setf (aref d i j) y)
       (setf (aref r i j) z)
       (cond
         ((and (>= x y) (>= x z))
          (setf (aref m i j) x) (setf (aref n i j) +match+))
         ((>= y z)
          (setf (aref m i j) y) (setf (aref n i j) +up+))
         (t
          (setf (aref m i j) z) (setf (aref n i j) +left+)))))))

(defun global-align (a b score-fn)
  (let ((m (make-array (list (1+ (length a)) (1+ (length b)))
                       :initial-element 0
                       :element-type '(signed-byte 31)))
        (n (make-array (list (1+ (length a)) (1+ (length b)))
                       :initial-element 0
                       :element-type '(signed-byte 31))))
    (declare (type (simple-array (signed-byte 31) (* *)) m n))
    (dotimes (i (1+ (length a)))
      (if (> i 0)
          (global-align-score m n i 0 (aref a (1- i)) +gap-char+ score-fn)
          (setf (aref m i 0) 0)))
    (dotimes (j (1+ (length b)))
      (if (> j 0)
          (global-align-score m n 0 j +gap-char+ (aref b (1- j)) score-fn)
          (setf (aref m 0 j) 0)))
    (do ((i 1 (1+ i)))
        ((> i (length a)))
      (do ((j 1 (1+ j)))
          ((> j (length b)))
          (global-align-score m n i j (aref a (1- i)) (aref b (1- j)) score-fn)))
    (let ((z (emit-global m n (length a) (length b) a b)))
      (make-alignment
       :score (aref m (length a) (length b))
       :seq1 (coerce (first z) 'string)
       :seq2 (coerce (second z) 'string)
       :dp-matrix m
       :dp-traceback n))))

(macrolet ((global-align-score-mac (m n i j k l score-fn)
             (alexandria:once-only (m n i j k l)
               `(cond
                  ((and (> ,i 0) (= ,j 0))
                   (let ((y (+ (aref ,m (1- ,i) ,j) 
                               (let ((*gap* (or *terminal-gap* *gap*)))
                                 (,score-fn ,k +gap-char+)))))
                     (setf (aref ,m ,i ,j) y
                           (aref ,n ,i ,j) +up+)))
                  ((and (= ,i 0) (> ,j 0))       
                   (let ((z (+ (aref ,m ,i (1- ,j))
                               (let ((*gap* (or *terminal-gap* *gap*)))
                                 (,score-fn +gap-char+ ,l)))))
                     (setf (aref ,m ,i ,j) z
                           (aref ,n ,i ,j) +left+)))
                  (t
                   (let ((x (+ (aref ,m (1- ,i) (1- ,j)) (,score-fn ,k ,l)))
                         (y (+ (aref ,m (1- ,i) ,j) (,score-fn ,k +gap-char+)))
                         (z (+ (aref ,m ,i (1- ,j)) (,score-fn +gap-char+ ,l))))
                     (cond
                       ((and (>= x y) (>= x z))
                        (setf (aref ,m ,i ,j) x
                              (aref ,n ,i ,j) +match+))
                       ((>= y z)
                        (setf (aref ,m ,i ,j) y
                              (aref ,n ,i ,j) +up+))
                       (t
                        (setf (aref ,m ,i ,j) z
                              (aref ,n ,i ,j) +left+))))))))
           (def-global-align-fun (fun-name score-fn)
             `(defun ,fun-name (a b)
                (let ((m (make-array (list (1+ (length a)) (1+ (length b)))
                                     :initial-element 0))
                      (n (make-array (list (1+ (length a)) (1+ (length b)))
                                     :initial-element 0
                                     :element-type '(unsigned-byte 2))))
                  (declare (type (simple-array (unsigned-byte 2) (* *)) n))
                  (setf (aref m 0 0) 0)
                  (let ((imax (length a))
                        (jmax (length b)))
                    (loop for i from 1 to imax
                       do (global-align-score-mac m n i 0 (aref a (1- i)) +gap-char+
                                                  (lambda (p q)
                                                    (or *terminal-gap*
                                                        (,score-fn p q)))))
                    (loop for j from 1 to jmax
                       do (global-align-score-mac m n 0 j +gap-char+ (aref b (1- j))
                                                  (lambda (p q)
                                                    (or *terminal-gap*
                                                        (,score-fn p q)))))

                    (loop for i from 1 below imax
                       do
                         (loop for j from 1 below jmax
                            do (global-align-score-mac m n i j
                                                       (aref a (1- i)) (aref b (1- j)) ,score-fn)))
                    (loop for i from 1 below imax
                       do (global-align-score-mac m n i jmax
                                                  (aref a (1- i))
                                                  (aref b (1- jmax))
                                                  (lambda (p q)
                                                    (let ((*gap* *terminal-gap*))
                                                      (,score-fn p q)))))
                    (loop for j from 1 to jmax
                       do (global-align-score-mac m n imax j
                                                  (aref a (1- imax))
                                                  (aref b (1- j))
                                                  (lambda (p q)
                                                    (let ((*gap* *terminal-gap*))
                                                      (,score-fn p q))))))
                  (let ((z (emit-global m n (length a) (length b) a b)))
                    (make-alignment
                     :score (aref m (length a) (length b))
                     :seq1 (coerce (first z) 'string)
                     :seq2 (coerce (second z) 'string)
                     :dp-matrix m
                     :dp-traceback n))))))
  
  (def-global-align-fun %global-align-aa aa-score)
  (def-global-align-fun %global-align-na na-score))


(defmethod global-align-aa ((seq1 string)
                            (seq2 string))
  (%global-align-aa seq1 seq2))

(defmethod global-align-aa ((seq1 aa-sequence-with-residues)
                            (seq2 aa-sequence-with-residues))
  (global-align-aa (residues-string seq1)
                   (residues-string seq2)))

(defmethod global-align-na ((seq1 string) (seq2 string)
                            &key (gap *gap*)
                                 (gap-extend *gap-extend*)
                                 (match *match*)
                                 (mismatch *mismatch*)
                                 (transition *transition*)
                                 (terminal-gap *terminal-gap*)
                                 (terminal-gap-extend *terminal-gap-extend*))
  (let ((*gap* gap)
        (*gap-extend* gap-extend)
        (*match* match)
        (*mismatch* mismatch)
        (*transition* transition)
        (*terminal-gap* terminal-gap)
        (*terminal-gap-extend* terminal-gap-extend))
    (%global-align-na seq1 seq2)))

(defmethod global-align-na ((seq1 na-sequence-with-residues)
                            (seq2 na-sequence-with-residues)
                            &rest args)
  (apply #'global-align-na (residues-string seq1)
         (residues-string seq2)
         args))

(defun global-align-affine-gaps (a b score-fn)
  (let ((m (make-array (list (1+ (length a)) (1+ (length b))) :initial-element 0))
        (n (make-array (list (1+ (length a)) (1+ (length b))) :initial-element 0))
        (d (make-array (list (1+ (length a)) (1+ (length b))) :initial-element 0))
        (r (make-array (list (1+ (length a)) (1+ (length b))) :initial-element 0)))
    (dotimes (i (1+ (length a)))
      (if (> i 0)
          (global-align-score-affine-gaps m n d r i 0 (aref a (1- i)) +gap-char+ score-fn)
          (setf (aref m i 0) 0)))
    (dotimes (j (1+ (length b)))
      (if (> j 0)
          (global-align-score-affine-gaps m n d r 0 j +gap-char+ (aref b (1- j)) score-fn)
          (setf (aref m 0 j) 0)))
    (do ((i 1 (1+ i)))
        ((> i (length a)))
        (do ((j 1 (1+ j)))
            ((> j (length b)))
          (global-align-score-affine-gaps m n d r i j
                                          (aref a (1- i)) (aref b (1- j)) score-fn)))
    (let ((z (emit-global m n (length a) (length b) a b)))
      (make-alignment
       :score (aref m (length a) (length b))
       :seq1 (coerce (first z) 'string)
       :seq2 (coerce (second z) 'string)
       :dp-matrix m
       :dp-down-matrix d
       :dp-right-matrix r
       :dp-traceback n))))

(defmethod global-align-aa-affine-gaps ((seq1 string) (seq2 string)
                                        &key (gap *gap*)
                                             (gap-extend *gap-extend*)
                                             (terminal-gap *terminal-gap*)
                                             (terminal-gap-extend *terminal-gap-extend*))
  (let ((*gap* gap)
        (*gap-extend* gap-extend)
        (*terminal-gap* terminal-gap)
        (*terminal-gap-extend* terminal-gap-extend))
    (global-align-affine-gaps seq1 seq2 #'aa-score)))

(defmethod global-align-aa-affine-gaps ((seq1 aa-sequence-with-residues)
                                        (seq2 aa-sequence-with-residues)
                                        &rest args)
  (apply #'global-align-aa-affine-gaps (residues-string seq1)
         (residues-string seq2)
         args))

(defmethod global-align-na-affine-gaps ((seq1 string) (seq2 string)
                                        &key (gap *gap*)
                                             (gap-extend *gap-extend*)
                                             (match *match*)
                                             (mismatch *mismatch*)
                                             (transition *transition*)
                                             (terminal-gap *terminal-gap*)
                                             (terminal-gap-extend *terminal-gap-extend*))
  (let ((*gap* gap)
        (*gap-extend* gap-extend)
        (*match* match)
        (*mismatch* mismatch)
        (*transition* transition)
        (*terminal-gap* terminal-gap)
        (*terminal-gap-extend* terminal-gap-extend))
    (global-align-affine-gaps seq1 seq2 #'na-score)))

(defmethod global-align-na-affine-gaps ((seq1 na-sequence-with-residues)
                                        (seq2 na-sequence-with-residues)
                                        &rest args)
  (apply #'global-align-na-affine-gaps
         (residues-string seq1)
         (residues-string seq2)
         args))


(defun emit-local (m n i j a b &optional s1 s2 s3 s4)
  (cond
    ((or (and (= i 0) (= j 0))
         (= (aref n i j) +terminate+)
         (= (aref m i j) 0))
     (list s1 s2 s3 s4))
    ((or (= i 0) (= (aref n i j) +left+))
     (emit-local m n i (1- j) a b
                 (cons #\- s1) (cons (aref b (1- j)) s2) s3 (cons (aref b (1- j)) s4)))
    ((or (= j 0) (= (aref n i j) +up+))
     (emit-local m n (1- i) j a b
                 (cons (aref a (1- i)) s1) (cons #\- s2) (cons (aref a (1- i)) s3) s4))
    (t
     (emit-local m n (1- i) (1- j) a b
                 (cons (aref a (1- i)) s1) (cons (aref b (1- j)) s2) (cons (aref a (1- i)) s3) (cons (aref b (1- j)) s4)))))

(defun local-align-score-affine-gaps (m n d r i j k l score-fn)
  (cond
    ((and (> i 0) (= j 0))
     (let ((y (max (+ (aref d (1- i) j) (if (> i 1) *gap-extend* *gap*))
                   (+ (aref m (1- i) j) (apply score-fn (list k +gap-char+))))))
       (if (> 0 y)
           (progn (setf (aref m i j) 0) (setf (aref n i j) +terminate+) 0)
           (progn (setf (aref m i j) y) (setf (aref n i j) +up+)))
       (setf (aref d i j) y)))
    ((and (= i 0) (> j 0))       
     (let ((z (max (+ (aref r i (1- j)) (if (> j 1) *gap-extend* *gap*))
                   (+ (aref m i (1- j)) (apply score-fn (list +gap-char+ l))))))
       (if (> 0 z)
           (progn (setf (aref m i j) 0) (setf (aref n i j) +terminate+) 0)
           (progn (setf (aref m i j) z) (setf (aref n i j) +left+)))
       (setf (aref r i j) z)))
    (t
     (let ((x (+ (aref m (1- i) (1- j)) (apply score-fn (list k l))))
           (y (max (+ (aref d (1- i) j) *gap-extend*)
                   (+ (aref m (1- i) j) (apply score-fn (list k +gap-char+)))))
           (z (max (+ (aref r i (1- j)) *gap-extend*)
                   (+ (aref m i (1- j)) (apply score-fn (list +gap-char+ l))))))
       (setf (aref d i j) y)
       (setf (aref r i j) z)
       (cond
         ((and (> 0 x) (> 0 y) (> 0 z))
          (setf (aref m i j) 0) (setf (aref n i j) +terminate+) 0)
         ((and (>= x y) (>= x z))
          (setf (aref m i j) x) (setf (aref n i j) +match+) x)
         ((>= y z)
          (setf (aref m i j) y) (setf (aref n i j) +up+) y)
         (t
          (setf (aref m i j) z) (setf (aref n i j) +left+) z))))))

(defgeneric local-align-affine-gaps (a b score-fn))

(defmethod local-align-affine-gaps (a b score-fn)
  (let ((m (make-array (list (1+ (length a)) (1+ (length b))) :initial-element 0))
        (n (make-array (list (1+ (length a)) (1+ (length b))) :initial-element 0))
        (d (make-array (list (1+ (length a)) (1+ (length b))) :initial-element 0))
        (r (make-array (list (1+ (length a)) (1+ (length b))) :initial-element 0))
        (maxscore 0)
        (maxi 0)
        (maxj 0))
    (dotimes (i (1+ (length a)))
      (setf (aref m i 0) 0))
    (dotimes (j (1+ (length b)))
      (setf (aref m 0 j) 0))
    (do ((i 1 (1+ i)))
        ((> i (length a)))
      (do ((j 1 (1+ j)))
          ((> j (length b)))
        (let ((s (local-align-score-affine-gaps m n d r i j
                                                (aref a (1- i)) (aref b (1- j)) score-fn)))
          (if (> s maxscore)
              (progn
                (setf maxscore s)
                (setf maxi i)
                (setf maxj j))))))
    (destructuring-bind (seq1 seq2 ungapped-seq1 ungapped-seq2)
        (emit-local m n maxi maxj a b)
      (make-local-alignment
       :score (aref m maxi maxj)
       :seq1 (coerce seq1 'string)
       :seq2 (coerce seq2 'string)
       :ungapped-seq1 (coerce ungapped-seq1 'string)
       :ungapped-seq2 (coerce ungapped-seq2 'string)
       :dp-matrix m
       :dp-down-matrix d
       :dp-right-matrix r
       :dp-traceback n
       :class 'local-alignment))))

(defun %local-align-aa-affine-gaps (a b)
  (local-align-affine-gaps a b #'aa-score))

(defmethod local-align-aa-affine-gaps ((seq1 aa-sequence-with-residues)
                                       (seq2 aa-sequence-with-residues))
  (%local-align-aa-affine-gaps (residues-string seq1)
                               (residues-string seq2)))

(defun %local-align-na-affine-gaps (a b)
  (local-align-affine-gaps a b #'na-score))

(defmethod local-align-na-affine-gaps ((seq1 na-sequence-with-residues)
                                       (seq2 na-sequence-with-residues))
  (%local-align-na-affine-gaps (residues-string seq1)
                               (residues-string seq2)))

(defmethod local-align-affine-gaps ((seq1 aa-sequence-with-residues)
                                    (seq2 aa-sequence-with-residues)
                                    score-fn)
  (local-align-affine-gaps (residues-string seq1)
                           (residues-string seq2)
                           score-fn))

(defun local-align-score (m n i j k l score-fn)
  (declare (type fixnum i j)
           (type base-char k l)
           (type (simple-array fixnum (* *)) n m))
  (cond
    ((and (> i 0) (= j 0))
     (let ((y (+ (aref m (1- i) j) (apply score-fn (list k +gap-char+)))))
       (declare (type fixnum y))
       (if (> 0 y)
           (progn
             (setf (aref m i j) 0
                   (aref n i j) +terminate+)
             0)
           (setf (aref m i j) y
                 (aref n i j) +up+))))
    ((and (= i 0) (> j 0))       
     (let ((z (+ (aref m i (1- j)) (apply score-fn (list +gap-char+ l)))))
       (declare (type fixnum z))
       (if (> 0 z)
           (progn (setf (aref m i j) 0) (setf (aref n i j) +terminate+) 0)
           (progn (setf (aref m i j) z) (setf (aref n i j) +left+)))))
    (t
     (let ((x (+ (aref m (1- i) (1- j)) (apply score-fn (list k l))))
           (y (+ (aref m (1- i) j) (apply score-fn (list k +gap-char+))))
           (z (+ (aref m i (1- j)) (apply score-fn (list +gap-char+ l)))))
       (declare (type fixnum x y z))
       (cond
         ((and (> 0 x) (> 0 y) (> 0 z))
          (setf (aref m i j) 0) (setf (aref n i j) +terminate+) 0)
         ((and (>= x y) (>= x z))
          (setf (aref m i j) x) (setf (aref n i j) +match+) x)
         ((>= y z)
          (setf (aref m i j) y) (setf (aref n i j) +up+) y)
         (t
          (setf (aref m i j) z) (setf (aref n i j) +left+) z))))))

(defun local-align (a b score-fn)
  (declare (type (simple-array character *) a b))
  (let ((m (make-array (list (1+ (length a)) (1+ (length b)))
                       :initial-element 0 :element-type 'fixnum))
        (n (make-array (list (1+ (length a)) (1+ (length b)))
                       :initial-element 0 :element-type 'fixnum))
        (maxscore 0)
        (maxi 0)
        (maxj 0)
        (lena (length a))
        (lenb (length b)))
    (declare (type fixnum maxscore))
    (dotimes (i (1+ lena))
      (setf (aref m i 0) 0))
    (dotimes (j (1+ lenb))
      (setf (aref m 0 j) 0))
    (do ((i 1 (1+ i)))
        ((> i lena))
      (declare (type fixnum i))
      (do ((j 1 (1+ j)))
          ((> j lenb))
        (declare (type fixnum j))
        (let ((s (local-align-score m n i j
                                    (aref a (1- i)) (aref b (1- j)) score-fn)))
          (if (> s maxscore)
              (progn
                (setf maxscore s)
                (setf maxi i)
                (setf maxj j))))))
    (destructuring-bind (seq1 seq2 ungapped-seq1 ungapped-seq2)
        (emit-local m n maxi maxj a b)
      (make-local-alignment
       :score (aref m maxi maxj)
       :seq1 (coerce seq1 'string)
       :seq2 (coerce seq2 'string)
       :ungapped-seq1 (coerce ungapped-seq1 'string)
       :ungapped-seq2 (coerce ungapped-seq2 'string)
       :dp-matrix m
       :dp-traceback n
       :class 'local-alignment))))

(defun %local-align-aa (a b)
  (local-align a b #'aa-score))

(defun %local-align-na (a b)
  (local-align a b #'na-score))

(defmethod local-align-aa ((seq1 aa-sequence-with-residues)
                           (seq2 aa-sequence-with-residues))
  (%local-align-aa (residues-string seq1)
                   (residues-string seq2)))

(defmethod local-align-na ((seq1 string)
                           (seq2 string)
                           &key
                             (gap *gap*)
                             (match *match*)
                             (mismatch *mismatch*))
  (let ((*gap* gap)
        (*match* match)
        (*mismatch* mismatch))
    (%local-align-na seq1 seq2)))

(defmethod local-align-na ((seq1 na-sequence-with-residues)
                            (seq2 na-sequence-with-residues)
                            &rest args)
  (apply #'local-align-na
         (residues-string seq1) (residues-string seq2)
         args))

(defun alignment-data (align)
  (cons
   (alignment-dp-matrix align)
   (multiple-value-list
    (alignment-results align))))
