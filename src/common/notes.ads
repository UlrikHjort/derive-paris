--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  What the game tells the terminal as it goes (tiles loaded, streets
--  closed, the road network's size...): only with PARIS_VERBOSE=1 set,
--  so that playing leaves the terminal quiet.  Errors and warnings are
--  printed always (and errors go to ~/.derive.log as well).

package Notes is

   function Verbose return Boolean;

   procedure Say (Text : String);
   --  Printed with PARIS_VERBOSE only

end Notes;
