(asdf:defsystem :funcle
  :description "funcle - a fun cl engine"
  :author "George Watson <thisisgeorgewatson@gmail.com>"
  :homepage "https:/github.com/takeiteasy/funcle"
  :license "GPLv3"
  :version "0.0.1"
  :depends-on (#:cl-raylib)
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "funcle")))