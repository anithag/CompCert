(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Bernhard Schommer, AbsInt Angewandte Informatik GmbH       *)
(*                                                                     *)
(*  AbsInt Angewandte Informatik GmbH. All rights reserved. This file  *)
(*  is distributed under the terms of the INRIA Non-Commercial         *)
(*  License Agreement.                                                 *)
(*                                                                     *)
(* *********************************************************************)

(* Printer for the Dwarf 2 debug information in ASM *)

open DwarfTypes
open DwarfUtil
open Printf
open PrintAsmaux
open Sections

(* The printer is parameterized over target specific functions and a set of dwarf type constants *)
module DwarfPrinter(Target: DWARF_TARGET):
    sig
      val print_debug: out_channel -> debug_entries -> unit
    end =
  struct

    open Target

    (* Byte value to string *)
    let string_of_byte value =
      sprintf "	.byte		%s\n" (if value then "0x1" else "0x0")

    (* Print a label *)
    let print_label oc lbl =
      fprintf oc "%a:\n" label lbl

    (* Print a positive label *)
    let print_plabel oc lbl =
      print_label oc (transl_label lbl)

    (* Helper functions for abbreviation printing *)
    let add_byte buf value =
      Buffer.add_string buf (string_of_byte value)

    let add_abbr_uleb v buf =
      Buffer.add_string buf (Printf.sprintf "	.uleb128	%d\n" v)

    let add_abbr_entry (v1,v2) buf =
      add_abbr_uleb v1 buf;
      add_abbr_uleb v2 buf

    let add_file_loc buf =
      let file,line = file_loc_type_abbr in
      add_abbr_entry (0x3a,file) buf;
      add_abbr_entry (0x3b,line) buf

    let add_type = add_abbr_entry (0x49,type_abbr)

    let add_name = add_abbr_entry (0x3,name_type_abbr)

    let add_byte_size = add_abbr_entry (0xb,byte_size_type_abbr)

    let add_member_size = add_abbr_entry (0xb,member_size_abbr)

    let add_high_pc = add_abbr_entry (0x12,high_pc_type_abbr)

    let add_low_pc = add_abbr_entry (0x11,low_pc_type_abbr)

    let add_declaration = add_abbr_entry (0x3c,declaration_type_abbr)

    let add_location loc buf =
      match loc with
      | None -> ()
      | Some (LocRef _) -> add_abbr_entry (0x2,location_ref_type_abbr) buf
      | Some (LocList _ )
      | Some (LocSymbol _)
      | Some (LocSimple _) -> add_abbr_entry (0x2,location_block_type_abbr) buf

    (* Dwarf entity to string function *)
    let abbrev_string_of_entity entity has_sibling =
      let buf = Buffer.create 12 in
      let add_attr_some v f =
        match v with
        | None -> ()
        | Some _ -> f buf in
      let prologue id =
        let has_child = match entity.children with
        | [] -> false
        | _ -> true in
        add_abbr_uleb id buf;
        add_byte buf has_child;
        if has_sibling then add_abbr_entry (0x1,sibling_type_abbr) buf;
      in
      (match entity.tag with
      | DW_TAG_array_type e ->
          prologue 0x1;
          add_attr_some e.array_type_file_loc add_file_loc;
          add_type buf
      | DW_TAG_base_type b ->
          prologue 0x24;
          add_byte_size buf;
          add_attr_some b.base_type_encoding (add_abbr_entry (0x3e,encoding_type_abbr));
          add_name buf
      | DW_TAG_compile_unit e ->
          prologue 0x11;
          add_abbr_entry (0x1b,comp_dir_type_abbr) buf;
          add_low_pc buf;
          add_high_pc buf;
          add_abbr_entry (0x13,language_type_abbr) buf;
          add_name buf;
          add_abbr_entry (0x25,producer_type_abbr) buf;
          add_abbr_entry (0x10,stmt_list_type_abbr) buf;
      | DW_TAG_const_type _ ->
          prologue 0x26;
          add_type buf
      | DW_TAG_enumeration_type e ->
          prologue 0x4;
          add_attr_some e.enumeration_file_loc add_file_loc;
          add_byte_size buf;
          add_attr_some e.enumeration_declaration add_declaration;
          add_attr_some e.enumeration_name add_name
      | DW_TAG_enumerator e ->
          prologue 0x28;
          add_attr_some e.enumerator_file_loc add_file_loc;
          add_abbr_entry (0x1c,value_type_abbr) buf;
          add_name buf
      | DW_TAG_formal_parameter e ->
          prologue 0x5;
          add_attr_some e.formal_parameter_file_loc add_file_loc;
          add_attr_some e.formal_parameter_artificial (add_abbr_entry (0x34,artificial_type_abbr));
          add_attr_some e.formal_parameter_name add_name;
          add_type buf;
          add_attr_some e.formal_parameter_variable_parameter (add_abbr_entry (0x4b,variable_parameter_type_abbr));
          add_location  e.formal_parameter_location buf
      | DW_TAG_label _ ->
          prologue 0xa;
          add_low_pc buf;
          add_name buf;
      | DW_TAG_lexical_block a ->
          prologue 0xb;
          add_attr_some a.lexical_block_high_pc add_high_pc;
          add_attr_some a.lexical_block_low_pc add_low_pc
      | DW_TAG_member e ->
          prologue 0xd;
          add_attr_some e.member_file_loc add_file_loc;
          add_attr_some e.member_byte_size add_byte_size;
          add_attr_some e.member_bit_offset (add_abbr_entry (0xc,bit_offset_type_abbr));
          add_attr_some e.member_bit_size (add_abbr_entry (0xd,bit_size_type_abbr));
          add_attr_some e.member_declaration add_declaration;
          add_attr_some e.member_name add_name;
          add_type buf;
          (match e.member_data_member_location with
          | None -> ()
          | Some (DataLocBlock __) -> add_abbr_entry (0x38,data_location_block_type_abbr) buf
          | Some (DataLocRef _) -> add_abbr_entry (0x38,data_location_ref_type_abbr) buf)
      | DW_TAG_pointer_type _ ->
          prologue 0xf;
          add_type buf
      | DW_TAG_structure_type e ->
          prologue 0x13;
          add_attr_some e.structure_file_loc add_file_loc;
          add_attr_some e.structure_byte_size add_member_size;
          add_attr_some e.structure_declaration add_declaration;
          add_attr_some e.structure_name add_name
      | DW_TAG_subprogram e ->
          prologue 0x2e;
          add_file_loc buf;
          add_attr_some e.subprogram_external (add_abbr_entry (0x3f,external_type_abbr));
          add_attr_some e.subprogram_high_pc add_high_pc;
          add_attr_some e.subprogram_low_pc add_low_pc;
          add_name buf;
          add_abbr_entry (0x27,prototyped_type_abbr) buf;
          add_attr_some e.subprogram_type add_type;
      | DW_TAG_subrange_type e ->
          prologue 0x21;
          add_attr_some e.subrange_type add_type;
          (match e.subrange_upper_bound with
          | None -> ()
          | Some (BoundConst _) -> add_abbr_entry (0x2f,bound_const_type_abbr) buf
          | Some (BoundRef _) -> add_abbr_entry (0x2f,bound_ref_type_abbr) buf)
      | DW_TAG_subroutine_type e ->
          prologue 0x15;
          add_attr_some e.subroutine_type add_type;
          add_abbr_entry (0x27,prototyped_type_abbr) buf
      | DW_TAG_typedef e ->
          prologue 0x16;
          add_attr_some e.typedef_file_loc add_file_loc;
          add_name buf;
          add_type buf
      | DW_TAG_union_type e ->
          prologue 0x17;
          add_attr_some e.union_file_loc add_file_loc;
          add_attr_some e.union_byte_size add_member_size;
          add_attr_some e.union_declaration add_declaration;
          add_attr_some e.union_name add_name
      | DW_TAG_unspecified_parameter e ->
          prologue 0x18;
          add_attr_some e.unspecified_parameter_file_loc add_file_loc;
          add_attr_some e.unspecified_parameter_artificial (add_abbr_entry (0x34,artificial_type_abbr))
      | DW_TAG_variable e ->
          prologue 0x34;
          add_file_loc buf;
          add_attr_some e.variable_declaration add_declaration;
          add_attr_some e.variable_external (add_abbr_entry (0x3f,external_type_abbr));
          add_location  e.variable_location buf;
          add_name buf;
          add_type buf
      | DW_TAG_volatile_type _ ->
          prologue 0x35;
          add_type buf);
      Buffer.contents buf

    let abbrev_start_addr = ref (-1)

    let curr_abbrev = ref 1

    (* Function to get unique abbreviation ids *)
    let next_abbrev () =
      let abbrev = !curr_abbrev in
      incr curr_abbrev;abbrev

    (* Mapping from abbreviation string to abbrevaiton id *)
    let abbrev_mapping: (string,int) Hashtbl.t = Hashtbl.create 7

    (* Look up the id of the abbreviation and add it if it is missing *)
    let get_abbrev entity has_sibling =
      let abbrev_string = abbrev_string_of_entity entity has_sibling in
      (try
        Hashtbl.find abbrev_mapping abbrev_string
      with Not_found ->
        let id = next_abbrev () in
        Hashtbl.add abbrev_mapping abbrev_string id;
        id)

    (* Compute the abbreviations of an entry and its children *)
    let compute_abbrev entry =
      entry_iter_sib (fun sib entry ->
        let has_sib = match sib with
        | None -> false
        | Some _ -> true in
        ignore (get_abbrev entry has_sib)) (fun _ -> ()) entry

    (* Print the debug_abbrev section using the previous computed abbreviations*)
    let print_abbrev oc =
      let abbrevs = Hashtbl.fold (fun s i acc -> (s,i)::acc) abbrev_mapping [] in
      let abbrevs = List.sort (fun (_,a) (_,b) -> Pervasives.compare a b) abbrevs in
      section oc Section_debug_abbrev;
      print_label oc !abbrev_start_addr;
      List.iter (fun (s,id) ->
        fprintf oc "	.uleb128	%d\n" id;
        output_string oc s;
        fprintf oc "	.uleb128	0\n";
        fprintf oc "	.uleb128	0\n\n")  abbrevs;
      fprintf oc "	.sleb128	0\n"

    let debug_start_addr = ref (-1)

    let debug_stmt_list = ref (-1)

    let entry_labels: (int,int) Hashtbl.t = Hashtbl.create 7

    (* Translate the ids to address labels *)
    let entry_to_label id =
      try
        Hashtbl.find entry_labels id
      with Not_found ->
        let label = new_label () in
        Hashtbl.add entry_labels id label;
        label

    let loc_labels: (int,int) Hashtbl.t = Hashtbl.create 7

    (* Translate the ids to address labels *)
    let loc_to_label id =
      try
        Hashtbl.find loc_labels id
      with Not_found ->
        let label = new_label () in
        Hashtbl.add loc_labels id label;
        label

    let print_loc_ref oc r =
      let ref = loc_to_label r in
      fprintf oc "	.4byte		%a\n" label ref


    (* Helper functions for debug printing *)
    let print_opt_value oc o f =
      match o with
      | None -> ()
      | Some o -> f oc o

    let print_flag oc b =
      output_string oc (string_of_byte b)

    let print_string oc s =
      fprintf oc "	.asciz		\"%s\"\n" s

    let print_uleb128 oc d =
      fprintf oc "	.uleb128	%d\n" d

    let print_sleb128 oc d =
      fprintf oc "	.sleb128	%d\n" d

    let print_byte oc b =
      fprintf oc "	.byte		0x%X\n" b

    let print_2byte oc b =
      fprintf oc "	.2byte		0x%X\n" b

    let print_ref oc r =
      let ref = entry_to_label r in
      fprintf oc "	.4byte		%a\n" label ref

    let print_file_loc oc = function
      | Some (Diab_file_loc (file,col)) ->
          fprintf oc "	.4byte		%a\n" label file;
          print_uleb128 oc col
      | Some (Gnu_file_loc (file,col)) ->
          fprintf oc "	.4byte		%l\n" file;
          print_uleb128 oc col
     | None -> ()

    let print_loc_expr oc = function
      | DW_OP_bregx (a,b) ->
          print_byte oc dw_op_bregx;
          print_uleb128 oc a;
          fprintf oc "	.sleb128	%ld\n" b
      | DW_OP_plus_uconst i ->
          print_byte oc dw_op_plus_uconst;
          print_uleb128 oc i
      | DW_OP_piece i ->
          print_byte oc dw_op_piece;
          print_uleb128 oc i
      | DW_OP_reg i ->
          if i < 32 then
            print_byte oc (dw_op_reg0 + i)
          else begin
            print_byte oc dw_op_regx;
            print_uleb128 oc i
          end

    let print_loc oc loc =
      match loc with
      | LocSymbol s ->
          print_sleb128 oc 5;
          print_byte oc dw_op_addr;
          fprintf oc "	.4byte		%a\n" symbol s
      | LocSimple e ->
          print_sleb128 oc (size_of_loc_expr e);
          print_loc_expr oc e
      | LocList e ->
          let size = List.fold_left (fun acc a -> acc + size_of_loc_expr a) 0 e in
          print_sleb128 oc size;
          List.iter (print_loc_expr oc) e
      | LocRef f ->  print_loc_ref oc f

    let print_list_loc oc = function
      | LocSymbol s ->
          print_2byte oc 5;
          print_byte oc dw_op_addr;
          fprintf oc "	.4byte		%a\n" symbol s
      | LocSimple e ->
          print_2byte oc (size_of_loc_expr e);
          print_loc_expr oc e
      | LocList e ->
          let size = List.fold_left (fun acc a -> acc + size_of_loc_expr a) 0 e in
          print_2byte oc size;
          List.iter (print_loc_expr oc) e
      | LocRef f ->  print_loc_ref oc f

    let print_data_location oc dl =
      match dl with
      | DataLocBlock e ->
          print_sleb128 oc (size_of_loc_expr e);
          print_loc_expr oc e
      | _ -> ()

    let print_addr oc a =
      fprintf oc "	.4byte		%a\n" label a

    let print_array_type oc at =
      print_file_loc oc at.array_type_file_loc;
      print_ref oc at.array_type

    let print_bound_value oc = function
      | BoundConst bc -> print_uleb128 oc bc
      | BoundRef br -> print_ref oc br

    let print_base_type oc bt =
      print_byte oc bt.base_type_byte_size;
      (match bt.base_type_encoding with
      | Some e ->
          let encoding = match e with
          | DW_ATE_address -> 0x1
          | DW_ATE_boolean -> 0x2
          | DW_ATE_complex_float -> 0x3
          | DW_ATE_float -> 0x4
          | DW_ATE_signed -> 0x5
          | DW_ATE_signed_char -> 0x6
          | DW_ATE_unsigned -> 0x7
          | DW_ATE_unsigned_char -> 0x8
          in
          print_byte oc encoding;
      | None -> ());
      print_string oc bt.base_type_name

    let print_compilation_unit oc tag =
      let version_string =
        if Version.buildnr <> "" && Version.tag <> "" then
          sprintf "%s, Build: %s, Tag: %s" Version.version Version.buildnr Version.tag
        else
          Version.version in
      let prod_name = sprintf "AbsInt Angewandte Informatik GmbH:CompCert Version %s:(%s,%s,%s,%s)"
          version_string Configuration.arch Configuration.system Configuration.abi Configuration.model in
      print_string oc (Sys.getcwd ());
      print_addr oc tag.compile_unit_low_pc;
      print_addr oc tag.compile_unit_high_pc;
      print_uleb128 oc 1;
      print_string oc tag.compile_unit_name;
      print_string oc prod_name;
      print_addr oc !debug_stmt_list

    let print_const_type oc ct =
      print_ref oc ct.const_type

    let print_enumeration_type oc et =
      print_file_loc oc et.enumeration_file_loc;
      print_uleb128 oc et.enumeration_byte_size;
      print_opt_value oc et.enumeration_declaration print_flag;
      print_opt_value oc et.enumeration_name print_string

    let print_enumerator oc en =
      print_file_loc oc en.enumerator_file_loc;
      print_sleb128 oc en.enumerator_value;
      print_string oc en.enumerator_name

    let print_formal_parameter oc fp =
      print_file_loc oc fp.formal_parameter_file_loc;
      print_opt_value oc fp.formal_parameter_artificial print_flag;
      print_opt_value oc fp.formal_parameter_name print_string;
      print_ref oc fp.formal_parameter_type;
      print_opt_value oc fp.formal_parameter_variable_parameter print_flag;
      print_opt_value oc fp.formal_parameter_location print_loc

    let print_tag_label oc tl =
      print_ref oc tl.label_low_pc;
      print_string oc tl.label_name


    let print_lexical_block oc lb =
      print_opt_value oc lb.lexical_block_high_pc print_addr;
      print_opt_value oc lb.lexical_block_low_pc print_addr

    let print_member oc mb =
      print_file_loc oc mb.member_file_loc;
      print_opt_value oc mb.member_byte_size print_byte;
      print_opt_value oc mb.member_bit_offset print_byte;
      print_opt_value oc mb.member_bit_size print_byte;
      print_opt_value oc mb.member_declaration print_flag;
      print_opt_value oc mb.member_name print_string;
      print_ref oc mb.member_type;
      print_opt_value oc mb.member_data_member_location print_data_location


    let print_pointer oc pt =
      print_ref oc pt.pointer_type

    let print_structure oc st =
      print_file_loc oc st.structure_file_loc;
      print_opt_value oc st.structure_byte_size print_uleb128;
      print_opt_value oc st.structure_declaration print_flag;
      print_opt_value oc st.structure_name print_string

    let print_subprogram_addr oc (s,e) =
      fprintf oc "	.4byte		%a\n" label e;
      fprintf oc "	.4byte		%a\n" label s

    let print_subprogram oc sp =
      print_file_loc oc (Some sp.subprogram_file_loc);
      print_opt_value oc sp.subprogram_external print_flag;
      print_opt_value oc sp.subprogram_high_pc print_addr;
      print_opt_value oc sp.subprogram_low_pc print_addr;
      print_string oc sp.subprogram_name;
      print_flag oc sp.subprogram_prototyped;
      print_opt_value oc sp.subprogram_type print_ref

    let print_subrange oc sr =
      print_opt_value oc sr.subrange_type print_ref;
      print_opt_value oc sr.subrange_upper_bound print_bound_value

    let print_subroutine oc st =
      print_opt_value oc st.subroutine_type print_ref;
      print_flag oc st.subroutine_prototyped

    let print_typedef oc td =
      print_file_loc oc td.typedef_file_loc;
      print_string oc td.typedef_name;
      print_ref oc td.typedef_type

    let print_union_type oc ut =
      print_file_loc oc ut.union_file_loc;
      print_opt_value oc ut.union_byte_size print_uleb128;
      print_opt_value oc ut.union_declaration print_flag;
      print_opt_value oc ut.union_name print_string

    let print_unspecified_parameter oc up =
      print_file_loc oc up.unspecified_parameter_file_loc;
      print_opt_value oc up.unspecified_parameter_artificial print_flag

    let print_variable oc var =
      print_file_loc oc (Some var.variable_file_loc);
      print_opt_value oc var.variable_declaration print_flag;
      print_opt_value oc var.variable_external print_flag;
      print_opt_value oc var.variable_location print_loc;
      print_string oc var.variable_name;
      print_ref oc var.variable_type

    let print_volatile_type oc vt =
      print_ref oc vt.volatile_type

    (* Print an debug entry *)
    let  print_entry oc entry =
      entry_iter_sib (fun sib entry ->
        print_label oc (entry_to_label entry.id);
        let has_sib = match sib with
        | None -> false
        | Some _ -> true in
        let id = get_abbrev entry has_sib in
        print_sleb128 oc id;
        (match sib with
        | None -> ()
        | Some s -> let lbl = entry_to_label s in
          fprintf oc "	.4byte		%a-%a\n" label lbl label !debug_start_addr);
        begin
          match entry.tag with
          | DW_TAG_array_type arr_type -> print_array_type oc arr_type
          | DW_TAG_compile_unit comp -> print_compilation_unit oc comp
          | DW_TAG_base_type bt -> print_base_type oc bt
          | DW_TAG_const_type ct -> print_const_type oc ct
          | DW_TAG_enumeration_type et -> print_enumeration_type oc et
          | DW_TAG_enumerator et -> print_enumerator oc et
          | DW_TAG_formal_parameter fp -> print_formal_parameter oc fp
          | DW_TAG_label lb -> print_tag_label oc lb
          | DW_TAG_lexical_block lb -> print_lexical_block oc lb
          | DW_TAG_member mb -> print_member oc mb
          | DW_TAG_pointer_type pt -> print_pointer oc pt
          | DW_TAG_structure_type st -> print_structure oc st
          | DW_TAG_subprogram sb -> print_subprogram oc sb
          | DW_TAG_subrange_type sb -> print_subrange oc sb
          | DW_TAG_subroutine_type st -> print_subroutine oc st
          | DW_TAG_typedef tp -> print_typedef oc tp
          | DW_TAG_union_type ut -> print_union_type oc ut
          | DW_TAG_unspecified_parameter up -> print_unspecified_parameter oc up
          | DW_TAG_variable var -> print_variable oc var
          | DW_TAG_volatile_type vt -> print_volatile_type oc vt
        end) (fun e ->
          if e.children <> [] then
          print_sleb128 oc 0) entry

    (* Print the debug abbrev section *)
    let print_debug_abbrev oc entries =
      List.iter (fun (_,_,_,e,_) -> compute_abbrev e) entries;
      print_abbrev oc

    (* Print the debug info section *)
    let print_debug_info oc start line_start entry  =
      Hashtbl.reset entry_labels;
      debug_start_addr:= start;
      debug_stmt_list:= line_start;
      print_label oc start;
      let debug_length_start = new_label ()  (* Address used for length calculation *)
      and debug_end = new_label () in
      fprintf oc "	.4byte		%a-%a\n" label debug_end label debug_length_start;
      print_label oc debug_length_start;
      fprintf oc "	.2byte		0x2\n"; (* Dwarf version *)
      print_addr oc !abbrev_start_addr; (* Offset into the abbreviation *)
      print_byte oc !Machine.config.Machine.sizeof_ptr; (* Sizeof pointer type *)
      print_entry oc entry;
      print_sleb128 oc 0;
      print_label oc debug_end (* End of the debug section *)

    let print_location_entry oc c_low l =
      print_label oc (loc_to_label l.loc_id);
      List.iter (fun (b,e,loc) ->
        fprintf oc "	.4byte		%a-%a\n" label b label c_low;
        fprintf oc "	.4byte		%a-%a\n" label e label c_low;
        print_list_loc oc loc) l.loc;
      fprintf oc "	.4byte	0\n";
      fprintf oc "	.4byte	0\n"

    let print_location_entry_abs oc l =
      print_label oc (loc_to_label l.loc_id);
      List.iter (fun (b,e,loc) ->
        fprintf oc "	.4byte		%a\n" label b;
        fprintf oc "	.4byte		%a\n" label e;
        print_list_loc oc loc) l.loc;
      fprintf oc "	.4byte	0\n";
      fprintf oc "	.4byte	0\n"


    let print_location_list oc (c_low,l) =
      let f =  match c_low with
      | Some s -> print_location_entry oc s
      | None -> print_location_entry_abs oc in
     List.iter f l

    let print_diab_entries oc entries =
      let abbrev_start = new_label () in
      abbrev_start_addr := abbrev_start;
      print_debug_abbrev oc entries;
      List.iter (fun (s,d,l,e,_) ->
        section oc (Section_debug_info s);
        print_debug_info oc d l e) entries;
      section oc Section_debug_loc;
      List.iter (fun (_,_,_,_,l) -> print_location_list oc l) entries

    let print_gnu_entries oc cp loc =
      compute_abbrev cp;
      let line_start = new_label ()
      and start = new_label ()
      and  abbrev_start = new_label () in
      abbrev_start_addr := abbrev_start;
      section oc (Section_debug_info "");
      print_debug_info oc start line_start cp;
      print_abbrev oc;
      section oc Section_debug_loc;
      print_location_list oc loc;
      section oc (Section_debug_line "");
      print_label oc line_start

    (* Print the debug info and abbrev section *)
    let print_debug oc = function
      | Diab entries -> print_diab_entries oc entries
      | Gnu (cp,loc) -> print_gnu_entries oc cp loc

  end
