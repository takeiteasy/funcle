(defpackage :funcle
  (:use :cl)
  (:export
  :world
   :make-world
   :set-current-world
   :set-default-world

    :entity
    :entity-id

    :define-entity

    :create-entity
    :destroy-entity
    :clear-entities
    :map-entities
    :all-entities

    :entity-created
    :entity-destroyed

    :define-aspect

    :define-system))
