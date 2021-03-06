open Thread
open Event

(* 3. *)

module CompressedTree = struct
  type 'a t = Leaf | Node of 'a * 'a t * 'a t
  type 'a c = CLeaf | Uneq of 'a * 'a c * 'a c | Eq of 'a * 'a c

  let rec compress t = 
    match t with 
    | Leaf -> CLeaf 
    | Node (v, l, r) -> if l = r then Eq (v, compress l) else Uneq (v, compress l, compress r)

  let rec count t = 
    match t with 
    | CLeaf -> 0
    | Eq (v, c) -> 1 + 2*(count c)
    | Uneq (v, l, r) -> 1 + (count l) + (count r)

  let rec merge f a b = 
    match a with 
    | CLeaf -> b 
    | Eq (va, ca) -> (match b with 
        | CLeaf -> a
        | Eq (vb, cb) -> Eq (f va vb, merge f ca cb)
        | Uneq (vb, lb, rb) -> let lnew = merge f ca lb in let rnew = merge f ca rb in
          if lnew = rnew then Eq (f va vb, lnew) else Uneq (f va vb, lnew, rnew))
    | Uneq (va, la, ra) -> (match b with
        | CLeaf -> a
        | Eq (vb, cb) -> let lnew = merge f la cb in let rnew = merge f ra cb in
          if lnew = rnew then Eq (f va vb, lnew) else Uneq (f va vb, lnew, rnew)
        | Uneq (vb, lb, rb) -> let lnew = merge f la lb in let rnew = merge f ra rb in
          if lnew = rnew then Eq (f va vb, lnew) else Uneq (f va vb, lnew, rnew)
      )
end

(* 4. *)
module Server : sig
  type ('a, 'b) t
  val serve : ('a -> 'b) -> ('a, 'b) t
  val request : ('a, 'b) t -> 'a -> 'b
end = struct
  type ('a, 'b) t = ('a option * 'b channel * 'b option) channel
  let serve f = let ch = new_channel () in
    let rec serve_func rep_t_list = 
      match select ((receive ch)::rep_t_list) with
      | (Some ra, rep, None) -> 
        let tch = new_channel () in
        let t_func () = sync (send tch (None, rep, Some (f ra))) in
        create t_func (); serve_func ((receive tch)::rep_t_list)
      | (None, rep, Some vb) -> sync (send rep vb); serve_func rep_t_list
      | _ -> Invalid_argument "erroneous request" |> raise
    in create serve_func []; ch
  let request server va = let ch = new_channel () in
    sync (send server (Some va, ch, None)); sync (receive ch)
end

(* 6. *)
module type Hashable = sig
  type t
  val hash : t -> int
end

(* 6.1 *)

module Memo (A: Hashable) : sig
  type 'a s (* state for results of type 'a *)
  val create : (A.t -> 'a) -> 'a s
  val eval : A.t -> 'a s -> 'a * 'a s (* result and new state *)
  val (%>) : ('a s -> 'a * 'a s) -> ('a -> 'a s -> 'b) -> 'a s -> 'b
end = struct
  type 'a tree = Node of int * (A.t * 'a) list * 'a tree * 'a tree | Empty
  type 'a s = (A.t -> 'a) * 'a tree
  let create f = (f, Empty)
  let eval v (f, t) = let rec search_tree t h =
                        match t with Empty -> let res = f v in (res, Node (A.hash v, [(v, res)], Empty, Empty))
                                   | Node (h2, res_list, l, r) -> if h2 < h then let (res, nl) = search_tree l h in (res, Node (h2, res_list, nl, r))
                                     else if h2 > h then let (res, nr) = search_tree r h in (res, Node (h2, res_list, l, nr))
                                     else match List.assoc_opt v res_list with 
                                       | Some res -> (res, Node (h2, res_list, l, r))
                                       | None ->  let res = f v in (res, Node(h2, (v, res)::res_list, l, r))
    in let (res, tree) = search_tree t (A.hash v) in (res, (f, tree))
  let (%>) f g s = let (res, state) = f s in g res state

end

(* 6.2 *)
module Int: Hashable = struct
  type t = int
  let hash i = i mod 1024
end

(* 6.3 *)
module Tuple (A:Hashable) (B:Hashable) : Hashable = struct
  type t = A.t * B.t
  let hash (a, b) = (A.hash a) + (B.hash b)
end

(* 6.4 *)
module Memo2 (A:Hashable) (B:Hashable):sig
  type 'a s (* state for results of type 'a *)
  val create : (A.t -> B.t -> 'a) -> 'a s
  val eval : A.t -> B.t -> 'a s -> 'a * 'a s (* result and new state *)
  val (%>) : ('a s -> 'a * 'a s) -> ('a -> 'a s -> 'b) -> 'a s -> 'b
end = struct
  module Tuple (A:Hashable) (B:Hashable) = struct
    type t = A.t * B.t
    let hash (a, b) = (A.hash a) + (B.hash b)
    let apply f (a,b) = f a b
    let create (a:A.t) (b:B.t) = (a,b)
  end
  module ABTuple = Tuple (A) (B)
  module MemoTuple = Memo (ABTuple)
  type 'a s = 'a MemoTuple.s
  let create f = MemoTuple.create (ABTuple.apply f)
  let eval a b s = MemoTuple.eval (ABTuple.create a b) s
  let (%>) f g s = MemoTuple.(%>) f g s

end


(* --- Test environment --*)

let () =
  print_string "Test server\n";
  let s = Server.serve (fun (x, s) -> delay x; print_string s; print_newline ()) in
  let t1 = create (fun _ -> Server.request s (0.5, "I was requested first but should be printed second")) () in 
  let t2 = create (fun _ -> delay 0.1; Server.request s (0.1, "I was requested second but should be printed first")) () in
  join t1; join t2;