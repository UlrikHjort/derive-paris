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

   procedure Set (Name, Value : String);
   --  Change a setting and write it to the file (the line is replaced, or
   --  added at the end with a comment)

end Config;
