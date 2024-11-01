; package.lisp 

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

(defpackage :funcle
  (:use :cl)
  (:local-nicknames (:rl :cl-raylib))
  (:export
   :world
   :make-world
   :set-current-world
   :set-default-world

   :entity
   :entity-id

   :define-entity

   :make-entity
   :destroy-entity
   :clear-entities
   :map-entities
   :all-entities

   :entity-created
   :entity-destroyed

   :define-trait

   :define-system

   :define-scene
   :scene->
   :push-scene
   :drop-scene
   :set-scene

   :define-game))
