; funcle.lisp

; Copyright (C) 2024  George Watson

; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.

; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <https://www.gnu.org/licenses/>.

(in-package :funcle)

;;;; Notes
;;; Entities are stored in an {id -> entity} hash table.
;;;
;;; Entities are also indexed by trait in a nested hash table:
;;;
;;;     {trait-symbol -> {id -> entity}}
;;;
;;; Entities are indexed by system too, as a vector of hash tables, one entry
;;; for each of the system's arguments:
;;;
;;;     {system-symbol ->
;;;        #({id -> entity}   ; arg1
;;;          {id -> entity})  ; arg2
;;;     }
;;;
;;; Systems are stored as:
;;;
;;;     {system-symbol -> (system-function arity type-specifier-list)}
;;;
;;; TODO: Figure out the distinct problem.

;;;; Global Data Structures ---------------------------------------------------
(defvar *trait-index* (make-hash-table))
(defvar *system-index* (make-hash-table))
(defvar *systems* (make-hash-table))

(defclass world ()
    ((entity-id-counter :initform 1
                        :accessor next-entity-id)
     (entity-index :initform (make-hash-table)
                   :accessor entities)
     (system-index :initform (make-hash-table)
                   :accessor system-index)))

(defvar *default-world* (make-instance 'world))
(defvar *world* *default-world*)

;;;; Utils --------------------------------------------------------------------
(defun symb (&rest args)
  (values (intern (format nil "~{~A~}" args))))


;;;; Entities -----------------------------------------------------------------
(defclass entity ()
    ((id :reader entity-id :initform (incf-id-counter *world*)
         :documentation
         "The unique ID of the entity.  This may go away in the future.")
     (%beast/traits :allocation :class :initform nil
                    :documentation
                    "A list of the traits this entity class inherits.  **Don't touch this.**"))
  (:documentation "A single entity in the game world."))

(defmethod print-object ((e entity) stream)
  (print-unreadable-object (e stream :type t :identity nil)
    (format stream "~D" (entity-id e))))


(defun entity-satisfies-system-type-specifier-p (entity specifier)
  (every (lambda (trait) (typep entity trait))
      specifier))

(defun index-entity (entity)
  "Insert `entity` into the entity index."
  (setf (gethash (entity-id entity) (entities *world*)) entity))

(defun index-entity-traits (entity)
  "Insert `entity` into appropriate trait indexes."
  (loop :for trait :in (slot-value entity '%beast/traits)
        :do (setf (gethash (entity-id entity)
                           (gethash trait *trait-index*))
              entity)))

(defun index-entity-systems (entity)
  "Insert `entity` into appropriate system indexes."
  (loop :with id = (entity-id entity)
        :for system :being :the hash-keys :of *systems*
        :using (hash-value (nil nil type-specifiers))
        :do (loop :for argument-index :across (gethash system *system-index*)
                  :for specifier :in type-specifiers
                    :when (entity-satisfies-system-type-specifier-p entity specifier)
                  :do (setf (gethash id argument-index) entity))))


(defun unindex-entity (id)
  "Remove `entity` from the entity-level index."
  (remhash id (entities *world*)))

(defun unindex-entity-traits (id)
  "Remove `entity` from the trait indexes."
  (loop :for index :being :the :hash-values :of *trait-index*
        :do (remhash id index)))

(defun unindex-entity-systems (id)
  "Remove `entity` from the system indexes."
  (loop :for argument-indexes :being :the hash-values :of *system-index*
        :do (loop :for index :across argument-indexes
                  :do (remhash id index))))


(defgeneric entity-created (entity)
  (:method ((entity entity)) nil)
  (:documentation
   "Called after an entity has been created and indexed.

  The default method does nothing, but users can implement their own auxillary
  methods to run code when entities are created.

  "))

(defgeneric entity-destroyed (entity)
  (:method ((entity entity)) nil)
  (:documentation
   "Called after an entity has been destroyed and unindexed.

  The default method does nothing, but users can implement their own auxillary
  methods to run code when entities are destroyed.

  "))


(defun make-entity (class &rest initargs)
  "Create an entity of the given entity class and return it.

  `initargs` will be passed along to `make-instance`.

  The `entity-created` generic function will be called just before returning the
  entity.

  "
  (let ((entity (apply #'make-instance class initargs)))
    (index-entity entity)
    (index-entity-traits entity)
    (index-entity-systems entity)
    (entity-created entity)
    entity))

(defun destroy-entity (entity)
  "Destroy `entity` and return it.

  The `entity-destroyed` generic function will be called after the entity has
  been destroyed and unindexed.

  "
  (let ((id (entity-id entity)))
    (unindex-entity id)
    (unindex-entity-traits id)
    (unindex-entity-systems id))
  (entity-destroyed entity)
  entity)

(defun clear-entities ()
  "Destroy all entities.

  `destroy-entity` will be called for each entity.

  Returns a list of all the destroyed entites.

  "
  (let ((entities (all-entities)))
    (mapc #'destroy-entity entities)
    entities))


(defun get-entity (id)
  "Return the entity with the given `id`, or `nil` if it is unknown."
  (gethash id (entities *world*)))

(defun all-entities ()
  "Return a list of all entities.

  Normally you should run code on entities using systems, but this function can
  be handy for debugging purposes.

  "
  (loop :for entity :being :the :hash-values :of (entities *world*)
        :collect entity))

(defun map-entities (function &optional (type 'entity))
  "Map `function` over all entities that are subtypes of `type`.

  Normally you should run code on entities using systems, but this function can
  be handy for debugging purposes.

  "
  (loop :for entity :being :the :hash-values :of (entities *world*)
          :when (typep entity type)
        :collect (funcall function entity)))


(defmacro define-entity (name traits &rest slots)
  "Define an entity class.

  `name` should be a symbol that will become the name of the class.

  `traits` should be a list of the traits this entity should inherit from.

  `slots` can be zero or more extra CLOS slot definitions.

  Examples:

    (define-entity potion (drinkable))

    (define-entity cheese (edible visible)
      (flavor :accessor cheese-flavor :initarg :flavor))

  "
  `(progn
    (defclass ,name (entity ,@traits)
      ((%beast/traits :allocation :class :initform ',traits)
       ,@slots))
    (defun ,(symb name '?) (object)
      (typep object ',name))
    (find-class ',name)))


;;;; Aspects ------------------------------------------------------------------
(defun initialize-trait-index (name)
  (when (not (gethash name *trait-index*))
        (setf (gethash name *trait-index*) (make-hash-table))))

(defmacro define-trait (name &rest fields)
  "Define an trait class.

  `name` should be a symbol that will become the name of the class.

  `fields` should be zero or more field definitions.  Each field definition can
  be a symbol (the field name), or a list of the field name and extra CLOS slot
  options.

  Field names will have the trait name and a slash prepended to them to create
  the slot names.  `:initarg` and `:accessor` slot options will also be
  automatically generated.

  Example:

    (define-trait edible
      energy
      (taste :initform nil))
    =>
    (defclass edible ()
      ((edible/energy :initarg :edible/energy
                      :accessor edible/energy)
       (edible/taste :initarg :edible/taste
                     :accessor edible/taste
                     :initform nil)))

  "
  (flet ((clean-field (f)
                      (ctypecase f
                        (symbol (list f))
                        (list f))))
    `(progn
      (defclass ,name ()
        ,(loop :for (field . field-options) :in (mapcar #'clean-field fields)
               :for field-name = (symb name '/ field)
               :collect `(,field-name
                           :accessor ,field-name
                           :initarg ,(intern (string field-name) :keyword)
                           ,@field-options)))

      (defun ,(symb name '?) (object)
        (typep object ',name))

      (initialize-trait-index ',name)

      (find-class ',name))))


;;;; Systems ------------------------------------------------------------------
(defun rebuild-system-index (arglist)
  (coerce (loop :for (nil . type-specifier) :in arglist
                :for index = (make-hash-table)
                :do (loop
                   :for entity :being :the :hash-values :of (entities *world*)
                     :when (entity-satisfies-system-type-specifier-p entity type-specifier)
                   :do (setf (gethash (entity-id entity) index) entity))
                :collect index)
          'vector))

(defun initialize-system-index (name function arglist)
  (setf (gethash name *systems*)
    (list function (length arglist) (mapcar #'cdr arglist))

    (gethash name *system-index*)
    (rebuild-system-index arglist)))


(defun build-system-runner (name type-specifiers)
  (unless (null type-specifiers)
    (let ((argument-indexes (gensym "AI"))
          (arguments (loop :repeat (length type-specifiers) :collect (gensym "E"))))
      `(let ((,argument-indexes (gethash ',name *system-index*)))
         ,(labels ((recur (types args n)
                          (if (null types)
                              `(,name ,@arguments)
                              `(loop :for ,(first args) :of-type ,(first types)
                                     :being :the :hash-values :of (aref ,argument-indexes ,n)
                                     :do ,(recur (rest types) (rest args) (1+ n))))))
            (recur type-specifiers arguments 0))))))


(defmacro define-system (name-and-options arglist &body body)
  "Define a system.

  `name-and-options` should be a list of the system name (a symbol) and any
  system options.  A bare symbol can be used if no options are needed.

  `arglist` should be a list of system arguments.  Each argument should be
  a list of the argument name and zero or more trait/entity classes.

  Defining a system `foo` defines two functions:

  * `foo` runs `body` on a single entity and should only be used for debugging,
    tracing, or disassembling.
  * `run-foo` should be called to run the system on all applicable entities.

  Available system options:

  * `:inline`: when true, try to inline the system function into the
    system-running function to avoid the overhead of a function call for every
    entity.  Defaults to `nil`.

  Examples:

    (define-system age ((entity lifetime))
      (when (> (incf (lifetime/age entity))
               (lifetime/lifespan entity))
        (destroy-entity entity)))

  "
  (let ((argument-type-specifiers
         (loop :for arg :in arglist ; either foo or (foo a1 a2)
               :for classes = (if (listp arg) (rest arg) nil)
               :collect `(and entity ,@classes))))
    (destructuring-bind (name &key inline) (if (listp name-and-options)
                                               name-and-options
                                               (list name-and-options))
      `(progn
        (declaim (ftype (function (,@argument-type-specifiers)
                                  (values null &optional))
                        ,name)
          ,(if inline
               `(inline ,name)
               `(notinline ,name)))
        (defun ,name (,@(mapcar #'car arglist))
          ,@body
          nil)

        (defun ,(symb 'run- name) ()
          ,(build-system-runner name argument-type-specifiers))

        (initialize-system-index ',name #',name ',arglist)

        ',name))))

(defun make-world ()
  (let ((w (make-instance 'world)))
    (maphash (lambda (k v)
               (declare (ignore v))
               (setf
                 (gethash k (system-index w))
                 (make-hash-table)))
             *system-index*)
    w))

(defmacro copy-hash-table (from to)
  `(maphash (lambda (k v)
              (setf (gethash k ,to) v))
            ,from))

(defmethod set-current-world ((w world))
  (copy-hash-table *system-index* (system-index *world*))
  (setf *world* w)
  (copy-hash-table (system-index *world*) *system-index*))

(defun set-default-world ()
  (set-current-world *default-world*))

(defmethod incf-id-counter ((w world))
  (incf (next-entity-id w)))

(defclass scene ()
    ((name :reader scene-name
           :initarg :name)
     (initialized :reader scene-initialized?
                  :accessor scene-initialized
                  :initform nil)
     (world :accessor scene-world
            :initform nil)
     (callbacks :initform (make-hash-table)
                :initarg :callbacks
                :accessor scene-callbacks)))

(defmacro make-scene (name &body callback-forms)
  `(make-instance 'scene
     :name ,name
     :callbacks (alexandria:plist-hash-table
                  (list ,@(loop :for (key fn) :in callback-forms
                                :collect key
                                :collect fn)))))

(defmacro define-scene (name &rest args)
  (let ((scene-name (format nil "~A" (symbol-name name))))
    `(funcle::register-scene ,scene-name (make-scene ,scene-name ,@args))))

(defmethod scene-> ((s scene) callback-key &rest args)
  (let ((cb (gethash callback-key (scene-callbacks s))))
    (when cb
          (apply cb args))))

(defvar *scenes* (make-hash-table :test 'equal))
(defvar *scene-history* nil)
(defvar *current-scene* nil)

(defun current-scene ()
  (gethash *current-scene* *scenes*))

(defun register-scene (name obj)
  (let ((n (coerce name 'simple-base-string)))
    (assert n)
    (when (nth-value 1 (gethash n *scenes*))
          (remhash n *scenes*))
    (setf (gethash name *scenes*) obj)))

(defun find-scene (obj)
  (gethash (cond
            ((stringp obj) (string-upcase (coerce obj 'simple-base-string)))
            ((and (typep obj 'standard-object) (typep obj 'scene)) (scene-name obj))
            (t nil))
           *scenes*))

(defun push-scene (obj)
  (let ((scene-obj (find-scene obj)))
    (when (and scene-obj
               (not (string= *current-scene* (scene-name scene-obj))))
          (when *current-scene*
                (scene-> (current-scene) :leaving)
                (setf *scene-history* (cons *current-scene* *scene-history*)))
          (if (member (scene-name scene-obj) *scene-history* :test #'string=)
              (loop :until (string= *current-scene* (scene-name scene-obj))
                    :do (drop-scene))
              (setf *current-scene* (scene-name scene-obj)))
          (if (scene-initialized? scene-obj)
              (progn
               (set-current-world (scene-world scene-obj))
               (scene-> scene-obj :resume))
              (progn
               (setf (scene-world scene-obj) (make-world))
               (set-current-world (scene-world scene-obj))
               (scene-> scene-obj :initialized))))))

(defun drop-scene (&optional n)
  (when *scene-history*
        (let ((current-scene (current-scene)))
          (scene-> current-scene :exiting)
          (setf
            *current-scene* (car *scene-history*)
            *scene-history* (cdr *scene-history*))
          (scene-> (current-scene) :resume)
          (when (and n (> n 0))
                (drop-scene (- n 1))))))

(defun call-exit-callback (key value)
  (declare (ignore key))
  (scene-> value :exiting)
  (setf (scene-initialized value) nil))

(defun set-scene (obj &key skip-exiting-callback)
  (when (null skip-exiting-callback)
        (maphash #'call-exit-callback *scenes*))
  (setf
    *scene-history* nil
    *current-scene* nil)
  (push-scene obj))

(defmacro define-game (&key
                       (window-width 800)
                       (window-height 600)
                       (window-title "funcle")
                       (clear-color :black)
                       initial-scene
                       target-fps
                       initialized
                       update
                       exiting)
  `(rl:with-window (,window-width ,window-height ,window-title)
     (when ,target-fps
           (rl:set-target-fps ,target-fps))
     (unwind-protect
         (progn
          (when ,initialized
                (funcall ,initialized))
          (when ,initial-scene
                (set-scene ,initial-scene))
          (loop until (rl:window-should-close)
                do (rl:with-drawing
                     (rl:clear-background ,clear-color)
                     (let ((delta-time (if (null ,target-fps)
                                           (/ (rl:get-frame-time) 1000.0) ;; delta time in milliseconds
                                           (/ 1.0 (coerce ,target-fps 'float)))))
                       (when *current-scene*
                             (scene-> (current-scene) :update delta-time)
                             (scene-> (current-scene) :draw))
                       (when ,update
                             (funcall ,update delta-time)))))
          (when ,exiting
                (funcall ,exiting))))))