type log_level =
  | STFU
  | ERROR
  | WARNING
  | INFO
  | DEBUG

val log_level : log_level ref
(** Setting [log_level] to a specific value will mute all messages above this level.
    Default: [INFO] *)

val color : bool ref
(** Setting [color] to [false] will prevent colored output.
    Default: [true] *)

val out_channel : out_channel ref
(** Setting [out_channel] to a specific channel will cause all functions to
    print to this channel.
    Default: [stdout] *)

val error : ('a, unit, string, 'b) format4 -> 'a
(** [error fmt ...] prints an error message according to [fmt].
    Terminates the program. *)

val errors : string list -> 'a
(** [errors errs] prints an error message for each error in [errs].
    Terminates the program. *)

val warn : ('a, unit, string, unit) format4 -> 'a
(** [warn fmt ...] prints a warning message according to [fmt]. *)

val info : ('a, unit, string, unit) format4 -> 'a
(** [info fmt ...] prints an informational message according to [fmt]. *)

val debug : ('a, unit, string, unit) format4 -> 'a
(** [debug fmt ...] prints a debug message accodring to [fmt]. *)

val confirm : default:bool -> ('a, unit, string, bool) format4 -> 'a
(** [confirm ~default fmt ...] asks the user for confirmation.
    Depending on [fmt] a question may be printed beforehand. *)

module Color : sig
  val red : string
  val green : string
  val yellow  : string
  val blue : string
  val magenta : string
  val cyan : string
  val reset : string
end
