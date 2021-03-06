;;; Identifiers
;;; Classes, generic functions, methods and functions for identifying
;;; bioloigcal sequences and features
;;;
;;; Copyright (c) 2006 Cyrus Harmon (ch-lisp@bobobeach.com)
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

(in-package :bio)

;;;
;;; identifier class

(defclass identifier (descriptor)
  ((id :accessor id :initarg :id)
   (type :accessor identifier-type :initarg :type)
   (version :accessor version :initarg :version)
   (authority :accessor authority :initarg :authority)))

(defclass identifier-set (bio-set) ())

;;; generic functions

(defgeneric get-ncbi-gis (described-object))
(defgeneric get-ncbi-loci (described-object))
(defgeneric get-refseq-ids (described-object))
(defgeneric get-genbank-accessions (described-object))

;;;
;;; identifier subclasses

(defclass ncbi-gi (identifier)
  ((id :accessor id :initarg :id :initarg :gi)
   (type :accessor identifier-type :initarg :type :initform "gi")
   (authority :accessor authority :initarg :authority :initform
  "ncbi")))

(defmethod get-ncbi-gis ((described described-object))
  (get-descriptors described :type 'ncbi-gi))

(defclass ncbi-pmid (identifier)
  ((id :accessor id :initarg :id :initarg :pmid)
   (type :accessor identifier-type :initarg :type :initform "pmid")
   (authority :accessor authority :initarg :authority :initform
  "ncbi")))

(defclass ncbi-geneid (identifier)
  ((id :accessor id :initarg :id :initarg :geneid)
   (type :accessor identifier-type :initarg :type :initform "geneid")
   (authority :accessor authority :initarg :authority :initform
              "ncbi")))

(defclass ncbi-locus (identifier)
  ((id :accessor id :initarg :id :initarg :locus)
   (type :accessor identifier-type :initarg :type :initform "locus")
   (authority :accessor authority :initarg :authority :initform
  "ncbi")))

(defmethod get-ncbi-loci ((described described-object))
  (get-descriptors described :type 'ncbi-locus))

(defclass refseq-id (identifier)
  ((id :accessor id :initarg :id :initarg :refseq-id)
   (type :accessor identifier-type :initarg :type :initform "refseq-id")
   (authority :accessor authority :initarg :authority :initform "ncbi")))

(defmethod get-refseq-ids ((described described-object))
  (get-descriptors described :type 'refseq-id))

(defclass genbank-accession (identifier)
  ((id :accessor id :initarg :id :initarg :accession)
   (type :accessor identifier-type :initarg :type :initform "accession")
   (authority :accessor authority :initarg :authority :initform "genbank")))

(defmethod get-genbank-accessions ((described described-object))
  (get-descriptors described :type 'genbank-accession))

(defclass affymetrix-probe-set-id (identifier)
  ((id :accessor id :initarg :id :initarg :accession)
   (type :accessor identifier-type :initarg :type :initform "probe-set-id")
   (authority :accessor authority :initarg :authority :initform "affymetrix")))

(defclass flybase-identifier (identifier)
  ((id :accessor id :initarg :id :initarg :flybase-id)
   (authority :accessor authority :initarg :authority :initform "flybase")))

(defclass flybase-gene-identifier (flybase-identifier)
  ((type :accessor identifier-type :initarg :type :initform "gene-identifier")))

(defclass flybase-symbol (flybase-identifier)
  ((type :accessor identifier-type :initarg :type :initform "symbol")))

