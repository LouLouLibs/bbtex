open Bbtex
let () =
  assert (Outline_window.html "<script>\"&" = "&lt;script&gt;&quot;&amp;");
  assert (Outline_window.route ~secret:"token" ~count:2 "POST" "/token/jump/1" = `Jump 1);
  List.iter (fun (meth, path) -> assert (Outline_window.route ~secret:"token" ~count:2 meth path = `Reject))
    ["GET", "/token/jump/1"; "POST", "/wrong/jump/1"; "POST", "/token/jump/2";
     "POST", "/token/jump/-1"; "POST", "/token/jump/01"; "POST", "/token/jump/0/../../etc/passwd"];
  assert (Outline_window.authorized ~host:"127.0.0.1:123" ["Host: 127.0.0.1:123"; "Origin: null"]);
  assert (not (Outline_window.authorized ~host:"127.0.0.1:123" ["Host: evil.test"; "Origin: null"]));
  assert (not (Outline_window.authorized ~host:"127.0.0.1:123" ["Host: 127.0.0.1:123"; "Origin: https://evil.test"]));
  let token = Outline_window.token () in
  assert (String.length token = 48 && token <> Outline_window.token ());
  print_endline "Outline prototype: escaped markup and restricted navigation requests passed"
