--  Dérive: open-world Paris in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  In-memory OSM data: nodes, ways, relations and tagged nodes, loaded
--  from an .osm XML file (the one-element-per-line layout written by the
--  OSM API and Overpass).

with Ada.Containers.Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;

package Osm_Model is

   subtype Osm_Id is Long_Long_Integer;

   function Hash_Id (Id : Osm_Id) return Ada.Containers.Hash_Type is
     (Ada.Containers.Hash_Type (Id mod 2**31));

   package Tag_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, String, Ada.Strings.Hash, "=");

   function Tag
     (Tags : Tag_Maps.Map; Key : String; Default : String := "") return String;

   function Has (Tags : Tag_Maps.Map; Key : String) return Boolean
     renames Tag_Maps.Contains;

   package Id_Vectors is new Ada.Containers.Vectors (Positive, Osm_Id);

   type Node_Pos is record
      Lat, Lon : Long_Float;
   end record;

   package Node_Maps is new Ada.Containers.Hashed_Maps
     (Osm_Id, Node_Pos, Hash_Id, "=");

   type Way_Rec is record
      Id   : Osm_Id;
      Refs : Id_Vectors.Vector;
      Tags : Tag_Maps.Map;
   end record;

   package Way_Vectors is new Ada.Containers.Vectors (Positive, Way_Rec);

   package Way_Index_Maps is new Ada.Containers.Hashed_Maps
     (Osm_Id, Positive, Hash_Id, "=");

   type Member_Role is (Outer, Inner, Other);

   type Member_Rec is record
      Is_Way : Boolean;
      Ref    : Osm_Id;
      Role   : Member_Role;
   end record;

   package Member_Vectors is new Ada.Containers.Vectors (Positive, Member_Rec);

   type Rel_Rec is record
      Id      : Osm_Id;
      Members : Member_Vectors.Vector;
      Tags    : Tag_Maps.Map;
   end record;

   package Rel_Vectors is new Ada.Containers.Vectors (Positive, Rel_Rec);

   type Point_Node is record
      Id   : Osm_Id;
      Pos  : Node_Pos;
      Tags : Tag_Maps.Map;
   end record;

   package Point_Vectors is new Ada.Containers.Vectors (Positive, Point_Node);

   type Model is record
      Nodes     : Node_Maps.Map;
      Ways      : Way_Vectors.Vector;
      Way_Index : Way_Index_Maps.Map;
      Rels      : Rel_Vectors.Vector;
      Points    : Point_Vectors.Vector;   --  nodes that carry tags
   end record;

   procedure Load (File_Name : String; M : in out Model);

end Osm_Model;
