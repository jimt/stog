(** *)
open Stog_types;;

let sort_by_name column (model : GTree.model) it_a it_b =
  let a = model#get ~row:it_a ~column in
  let b = model#get ~row:it_b ~column in
  Pervasives.compare a b
;;

let sort_by_date column (model : GTree.model) it_a it_b =
  let a = model#get ~row:it_a ~column in
  let b = model#get ~row:it_b ~column in
  Pervasives.compare a b
;;

let inv_sort f model it_a it_b =
  f model it_b it_a
;;

type art_model = {
  store : GTree.list_store ;
  model : GTree.model_sort ;
  col_id : Stog_types.article_id GTree.column ;
  col_title : string GTree.column ;
  col_date : Stog_types.date GTree.column ;
  }

let make_model () =
  let cols = new GTree.column_list in
  let id_col = cols#add Gobject.Data.caml in
  let title_col = cols#add Gobject.Data.string in
  let date_col = cols#add Gobject.Data.caml in
  let l = GTree.list_store cols in
  (*print_flags "ListStore" l ;*)
  (*List.iter
    (fun (stock_id, str, vis, date) ->
      let row = l#append () in
      l#set ~row ~column:stock_id_col stock_id ;
      l#set ~row ~column:str_col str ;
      l#set ~row ~column:vis_col vis ;
      l#set ~row ~column:date_col date)
    data ;
  *)
  let sortable = GTree.model_sort l in
  (*print_flags "TreeModelSort" sortable ;*)
  let sorts =
    [ 1, sort_by_name title_col;
      2, sort_by_date date_col;
    ]
  in
  ignore
  (sortable#connect#sort_column_changed
   (fun () ->
      match sortable#get_sort_column_id with
      | None -> ()
      | Some (id, k)  ->
          try
            let f = List.assoc id sorts in
            sortable#set_sort_func id f
          with
            Not_found ->
              ()
   )
  );
  { store = l ;
    model = sortable ;
    col_id = id_col ;
    col_title = title_col ;
    col_date = date_col ;
  }


let make_view ?packing art_model =
  let col_title =
    let col = GTree.view_column ~title:"Title" () in

    let str_renderer = GTree.cell_renderer_text [ `FAMILY "monospace" ; `XALIGN 0. ] in
    col#pack str_renderer ;
    col#add_attribute str_renderer "text" art_model.col_title ;

    col#set_sort_column_id 1 ;
    col
  in

  let col_date =
    let col = GTree.view_column ~title:"Date" () in
    let str_renderer = GTree.cell_renderer_text [ `XALIGN 0. ] in
    col#pack str_renderer ;
    col#set_cell_data_func str_renderer
      (fun model row ->
       let date = model#get ~row ~column:art_model.col_date in
       str_renderer#set_properties
       [ `TEXT (Stog_gui_misc.to_utf8 (Stog_types.string_of_date date)) ]) ;
    col#set_sort_column_id 2 ;
    col
  in

  let v = GTree.view ~model: art_model.model ?packing () in
  ignore(v#append_column col_title);
  ignore(v#append_column col_date) ;
  v
;;

class articles_box ?packing () =
  let model = make_model () in
  let view = make_view ?packing model in
  object(self)
    val mutable selection = None

    method view = view
    method private insert_article (id, art) =
      let row = model.store#append () in
      model.store#set ~row ~column:model.col_id id;
      model.store#set ~row ~column:model.col_title (Stog_gui_misc.to_utf8 art.art_title) ;
      model.store#set ~row ~column:model.col_date art.art_date

    method set_articles l =
      model.store#clear () ;
      List.iter self#insert_article l

    val mutable on_select = (fun _ -> ())
    method set_on_select
      (f : Stog_types.article_id -> unit) = on_select <- f

    val mutable on_unselect = (fun _ -> ())
    method set_on_unselect
      (f : Stog_types.article_id -> unit) = on_unselect <- f

    val mutable selection_changing = false
    method on_selection_changed () =
      if selection_changing then ()
      else
        begin
          selection_changing <- true;
          let continue =
            match selection with
              None -> true
            | Some (path, id) ->
                if view#selection#path_is_selected path then
                  true
                else
                  (
                   try
                     on_unselect id;
                     selection <- None;
                     true
                   with e ->
                       let msg =
                         match e with
                           Failure msg -> msg
                         | e -> Printexc.to_string e
                       in
                       GToolbox.message_box "Error"
                       (Stog_gui_misc.to_utf8 msg);
                       view#selection#select_path path;
                       false
                  )
          in
          if continue then
            begin
              match view#selection#get_selected_rows with
                [] -> selection <- None
              | path :: _ ->
                  let it = view#model#get_iter path in
                  let id = model.model#get ~row: it ~column: model.col_id in
                  selection <- Some (path, id);
                  on_select id
            end;
          selection_changing <- false
        end

    initializer
      ignore (view#selection#connect#changed self#on_selection_changed);
  end
;;

let make_field_table ?packing fields =
  let table = GPack.table
    ~columns:2 ~rows:(List.length fields)
    ?packing ()
  in
  let f top (text, w) =
    let label = GMisc.label ~text: (text^":") ~xpad: 2 ~xalign: 1. () in
    table#attach ~top ~left: 0 ~expand: `NONE label#coerce;
    table#attach ~top ~left: 1 ~expand: `X w#coerce;
    top+1
  in
  ignore (List.fold_left f 0 fields);
  table
;;

class edition_box ?packing () =
  let vbox = GPack.vbox ?packing () in
  let we_title = GEdit.entry () in
  let we_date = GEdit.entry () in
  let we_topics = GEdit.entry () in
  let we_keywords = GEdit.entry () in
  let fields = [
      "Title", we_title ; "Date", we_date ;
      "Topics", we_topics; "Keywords", we_keywords ]
  in
  let _table = make_field_table ~packing: vbox#pack fields in
  let wscroll = GBin.scrolled_window
    ~hpolicy: `AUTOMATIC ~vpolicy: `AUTOMATIC
    ~packing: (vbox#pack ~expand: true ~fill: true) ()
  in
  let body_view = GSourceView2.source_view ~packing: wscroll#add () in
  object(self)
    method box = vbox

    method clear () =
      we_title#set_text "";
      we_date#set_text "";
      we_topics#set_text "";
      we_keywords#set_text "";
      let b = body_view#source_buffer in
      b#delete ~start: b#start_iter ~stop: b#end_iter

    method set_article a =
      we_title#set_text (Stog_gui_misc.to_utf8 a.art_title);
      let (y,m,d) = a.art_date in
      we_date#set_text (Printf.sprintf "%04d/%02d/%02d" y m d);
      we_topics#set_text
      (Stog_gui_misc.to_utf8 (String.concat ", " a.art_topics));
      we_keywords#set_text
      (Stog_gui_misc.to_utf8 (String.concat ", " a.art_keywords));
      let b = body_view#source_buffer in
      b#delete ~start: b#start_iter ~stop: b#end_iter;
      b#insert (Stog_gui_misc.to_utf8 (Printf.sprintf "<->\n%s" a.art_body));

    method get_article a =
      let contents =
        Printf.sprintf
          "title: %s\ndate: %s\ntopics: %s\nkeywords: %s\n%s"
        (Stog_gui_misc.of_utf8 we_title#text)
        (Stog_gui_misc.of_utf8 we_date#text)
        (Stog_gui_misc.of_utf8 we_topics#text)
        (Stog_gui_misc.of_utf8 we_keywords#text)
        (Stog_gui_misc.of_utf8 (body_view#source_buffer#get_text ()))
      in
      Stog_io.read_article_main a contents

    initializer
      (*List.iter
        (fun l -> prerr_endline l#name)
        (Gtksv_utils.available_source_languages ());*)
      let lang_xml = Gtksv_utils.source_language_by_name "HTML" in
      Gtksv_utils.register_source_view body_view;
      Gtksv_utils.apply_sourceview_props
        body_view (Gtksv_utils.read_sourceview_props());
      Gtksv_utils.register_source_buffer body_view#source_buffer;
      Gtksv_utils.apply_source_style_scheme_to_registered_buffers
      (Gtksv_utils.read_style_scheme_selection ());
      body_view#source_buffer#set_highlight_syntax true;
      body_view#source_buffer#set_language lang_xml;
      body_view#set_wrap_mode `WORD;

  end
;;



