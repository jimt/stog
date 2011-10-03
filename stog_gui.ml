(** *)

let () = ignore(GMain.Main.init());;


let options = [];;

let main () =
  let dirs = ref [] in
  Arg.parse options
  (fun s -> dirs := s :: ! dirs)
  (Printf.sprintf "Usage: %s [options] [directories]\n where options are:" Sys.argv.(0));
  let dirs = match !dirs with [] -> [Filename.current_dir_name] | _ -> List.rev !dirs in
  let stogs = List.map Stog_io.read_stog dirs in
  let w = new Stog_gui_main.main_window stogs in
  w#window#show();
  GMain.Main.main ()
;;

Stog_misc.safe_main main;;