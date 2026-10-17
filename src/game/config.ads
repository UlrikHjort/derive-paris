--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Settings from ~/.deriverc: "name = value" lines, '#' starts a comment.
--  A commented starter file is written when there is none.

package Config is

   procedure Load;

   function Get (Name : String; Default : Float) return Float;
   function Get (Name : String; Default : Boolean) return Boolean;
   function Get (Name : String; Default : String) return String;

end Config;
