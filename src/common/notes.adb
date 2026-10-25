--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Environment_Variables;
with Ada.Text_IO;

package body Notes is

   Checked, On : Boolean := False;

   function Verbose return Boolean is
   begin
      if not Checked then
         On := Ada.Environment_Variables.Exists ("PARIS_VERBOSE");
         Checked := True;
      end if;
      return On;
   end Verbose;

   procedure Say (Text : String) is
   begin
      if Verbose then
         Ada.Text_IO.Put_Line (Text);
      end if;
   end Say;

end Notes;
