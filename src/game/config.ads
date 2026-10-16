--  Settings from ~/.deriverc: "name = value" lines, '#' starts a comment.
--  A commented starter file is written when there is none.

package Config is

   procedure Load;

   function Get (Name : String; Default : Float) return Float;
   function Get (Name : String; Default : Boolean) return Boolean;

end Config;
