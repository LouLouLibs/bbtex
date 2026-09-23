open Bbtex
open Preview_service

let contains text part = Project_index.find text 0 part < String.length text

let () =
  let xml = to_xml (Dict ["a & <b>", String "x < y > z & \"q\"";
                          "list", Array [Bool true; Integer 11; Array []];
                          "raw", Raw "\n<dict><key>k</key><true/></dict>\n"]) in
  assert (String.starts_with ~prefix:"<?xml version=\"1.0\" encoding=\"UTF-8\"?>" xml);
  assert (contains xml "<key>a &amp; &lt;b&gt;</key>");
  assert (contains xml "<string>x &lt; y &gt; z &amp; \"q\"</string>");
  assert (contains xml "\t\t<true/>\n\t\t<integer>11</integer>\n\t\t<array>\n\t\t</array>");
  assert (contains xml "\t<dict><key>k</key><true/></dict>\n");
  assert (String.ends_with ~suffix:"</dict>\n</plist>\n" xml);
  Random.self_init ();
  let id = uuid () in
  assert (String.length id = 36 && id.[14] = '4' && String.contains "89AB" id.[19]);
  assert (List.map String.length (String.split_on_char '-' id) = [8; 4; 4; 4; 12]);
  assert (uuid () <> uuid ());
  let info = to_xml (info ()) in
  assert (contains info "<string>org.bbtex.preview-selection</string>" &&
          contains info "<string>com.barebones.bbedit</string>");
  print_endline "Preview service: plist escaping, nesting, raw values, UUIDs and service info passed"
