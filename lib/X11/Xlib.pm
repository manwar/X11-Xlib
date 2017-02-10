package X11::Xlib;

use 5.008000;

use strict;
use warnings;
use base qw(Exporter);
use Carp;
use Try::Tiny;
use XSLoader;

our $VERSION = '0.03';

XSLoader::load(__PACKAGE__, $VERSION);

my %_constants= (
# BEGIN GENERATED XS CONSTANT LIST
  const_cmap => [qw( AllocAll AllocNone )],
  const_error => [qw( BadAccess BadAlloc BadAtom BadColor BadCursor BadDrawable
    BadFont BadGC BadIDChoice BadImplementation BadLength BadMatch BadName
    BadPixmap BadRequest BadValue BadWindow )],
  const_event => [qw( ButtonPress ButtonRelease CirculateNotify ClientMessage
    ColormapNotify ConfigureNotify CreateNotify DestroyNotify EnterNotify
    Expose FocusIn FocusOut GraphicsExpose GravityNotify KeyPress KeyRelease
    KeymapNotify LeaveNotify MapNotify MappingNotify MotionNotify NoExpose
    PropertyNotify ReparentNotify ResizeRequest SelectionClear SelectionNotify
    SelectionRequest UnmapNotify VisibilityNotify )],
  const_visual => [qw( VisualAllMask VisualBitsPerRGBMask VisualBlueMaskMask
    VisualClassMask VisualColormapSizeMask VisualDepthMask VisualGreenMaskMask
    VisualIDMask VisualRedMaskMask VisualScreenMask )],
# END GENERATED XS CONSTANT LIST
);
my %_functions= (
# BEGIN GENERATED XS FUNCTION LIST
  fn_conn => [qw( ConnectionNumber XCloseDisplay XOpenDisplay XSetCloseDownMode
    )],
  fn_event => [qw( XCheckMaskEvent XCheckTypedEvent XCheckTypedWindowEvent
    XCheckWindowEvent XFlush XNextEvent XPutBackEvent XSelectInput XSendEvent
    XSync )],
  fn_key => [qw( IsFunctionKey IsKeypadKey IsMiscFunctionKey IsModifierKey
    IsPFKey IsPrivateKeypadKey XGetKeyboardMapping XKeysymToKeycode
    XKeysymToString XStringToKeysym )],
  fn_screen => [qw( DefaultVisual DisplayHeight DisplayWidth RootWindow
    XCreateColormap XGetVisualInfo XMatchVisualInfo XVisualIDFromVisual )],
  fn_window => [qw(  )],
  fn_xtest => [qw( XBell XQueryKeymap XTestFakeButtonEvent XTestFakeKeyEvent
    XTestFakeMotionEvent )],
# END GENERATED XS FUNCTION LIST
);
our %EXPORT_TAGS= (
    %_constants,
    %_functions,
    constants => [ map { @$_ } values %_constants ],
    functions => [ map { @$_ } values %_functions ],
    all => [ map { @$_ } values %_constants, values %_functions ],
);

sub new {
    require X11::Xlib::Display;
    my $class= shift;
    X11::Xlib::Display->new(@_);
}

# Used by XS.  In the spirit of letting perl users violate encapsulation
#  as needed, the XS code exposes its globals to Perl.
our (
    %_connections,              # weak-ref set of all connection objects, keyed by *raw pointer*
    $_error_nonfatal_installed, # boolean, whether handler is installed
    $_error_fatal_installed,    # boolean, whether handler is installed
    $_error_fatal_trapped,      # boolean, whether Xlib is dead from fatal error
    $on_error_cb,               # application-supplied callback
);
sub on_error {
    ref($_[-1]) eq 'CODE' or croak "Expected coderef";
    $on_error_cb= $_[-1];
    X11::Xlib::_install_error_handlers(1,1);
}
# called by XS, if installed
sub _error_nonfatal {
    my $event= shift;
    my $dpy= $event->display;
    if ($on_error_cb) {
        try { $on_error_cb->($dpy, $event); }
        catch { warn $_; };
    }
    if ($dpy && $dpy->can('on_error_cb') && $dpy->on_error_cb) {
        try { $dpy->on_error_cb->($dpy, $event); }
        catch { warn $_; };
    }
}
# called by XS, if installed
sub _error_fatal {
    my $conn= shift;
    $conn->_mark_dead; # this connection is dead immediately

    if ($on_error_cb) {
        try { $on_error_cb->($conn); }
        catch { warn $_; };
    }
    # also call a user callback in any Display object
    for my $dpy (values %X11::Xlib::_displays) {
        next unless defined $dpy && defined $dpy->on_error_cb;
        try { $dpy->on_error_cb->($dpy); }
        catch { warn $_; };
    }

    # Kill all X11 connections, since Xlib internal state might be toast after this
    $_->_mark_dead for grep { defined } values %_connections;
}

1;

__END__


=head1 NAME

X11::Xlib - Low-level access to the X11 library

=head1 SYNOPSIS

  use X11::Xlib;
  my $display = X11::Xlib::Display->new();
  ...

=head1 DESCRIPTION

This module provides low-level access to X11 libary functions.

This includes access to some X11 extensions like the X11 test library (Xtst).

If you import the Xlib functions directly, or call them as methods on an
instance of X11::Xlib, you get a near-C<C> experience where you are required to
manage the lifespan of resources, XIDs are integers instead of objects, and the
library doesn't make any attempt to keep you from passing bad data to Xlib.

If you instead create a L<X11::Xlib::Display> object and call all your methods
on that, you get a more friendly wrapper around Xlib that helps you manage
resource lifespan, wraps XIDs with perl objects, and does some sanity checking
on the state of the library when you call methods.

=cut

=head1 FUNCTIONS

Most functions can be called as methods on the Xlib connection object, since
this is usually the first argument.  All functions which are part of Xlib's API
can be exported.

=head2 new

This is an alias for C<< X11::Xlib::Display->new >>, to help encourage using
the object oriented interface.

=head2 install_error_handlers

  X11::Xlib::install_error_handlers( $bool_nonfatal, $bool_fatal );

Error handling in Xlib is pretty bad.  The first problem is that non-fatal
errors are reported asynchronously in an API that pretends to be synchronous.
This is mildly annoying.  This library eases the pain by giving you a nice
L<XEvent|X11::Xlib::XEvent> object to work with, and the ability to deliver
the errors to a callback on your display or window object.

The second much larger problem is that fatal errors (like losing the connection
to the server) cause a mandatory termination of the host program.  Seriously.
The default behavior of Xlib is to print a message and abort, but even if you
install the C error handler to try to gracefully recover, when the error
handler returns Xlib still kills your program.  Under normal circumstances you
would have to perform all cleanup with your stack tied up through Xlib, but
this library cheats by using croak (C<longjmp>) to escape the callback and let
you wrap up your script in a normal manner.  <b>However</b>, after a fatal
error Xlib's internal state could be dammaged, so it is unsafe to make any more
Xlib calls.  The library tries to help assert this by invalidating all the
connection objects.

If you really need your program to keep running your best bet is to state-dump
to shared memory and then exec() a fresh copy of your script and reload the
dumped state.  Or use XCB instead of Xlib.

=head1 XLIB API

=head2 CONNECTION FUNCTIONS

=head3 XOpenDisplay

  my $display= X11::Xlib::XOpenDisplay($connection_string);

Instantiate a new L</Display> object. This object contains the connection to
the X11 display.  This will be an instance of C<X11::Xlib>.
The L<X11::Xlib::Display> object constructor is recommended instead.

The C<$connection_string> variable specifies the display string to open.
(C<"host:display.screen">, or often C<":0"> to connect to the only screen of
the only display on C<localhost>)
If unset, Xlib uses the C<$DISPLAY> environement variable.

If the handle goes out of scope, its destructor calls C<XCloseDisplay>, unless
you already called C<XCloseDisplay> or the X connection was lost.  (Be sure to
read the notes under L</install_error_handlers>

=head3 XCloseDisplay

  XCloseDisplay($display);
  # or, just:
  undef $display

Close a handle returned by XOpenDisplay.  You do not need to call this method
since the handle's destructor does it for you, unless you want to forcibly
stop communicating with X and can't track down your references.  Once closed,
all further Xlib calls on the handle will die with an exception.

=head3 ConnectionNumber

  my $fh= IO::Handle->new_from_fd( $display->ConnectionNumber, 'w+' );

Return the file descriptor (integer) of the socket connected to the server.
This is useful for select/poll designs.
(See also: L<X11::Xlib::Display->wait_event|X11::Xlib::Display/wait_event>)

=head3 XSetCloseDownMode

  XSetCloseDownMode($display, $close_mode)

Determines what resources are freed upon disconnect.  See X11 documentation.

=head2 COMMUNICATION FUNCTIONS

Most of these functions return an L</XEvent> by way of an "out" parameter that
gets overwritten during the call, in the style of C.  You may pass in an
undefined scalar to be automatically allocated for you.

=head3 XNextEvent

  XNextEvent($display, my $event_return)
  ... # event scalar is populated with event

You probably don't want this.  It blocks forever until an event arrives.
I added it for completeness.  See L<X11::Xlib::Display/wait_event>
for a more Perl-ish interface.

=head3 XCheckMaskEvent

=head3 XCheckWindowEvent

=head3 XCheckTypedEvent

=head3 XCheckTypedWindowEvent

  if ( XCheckMaskEvent($display, $event_mask, my $event_return) ) ...
  if ( XCheckTypedEvent($display, $event_type, my $event_return) ) ...
  if ( XCheckWindowEvent($display, $event_mask, $window, my $event_return) ) ...
  if ( XCheckTypedWindowEvent($display, $event_type, $window, my $event_return) ) ...

Each of these variations checks whether there is a matching event received from
the server and not yet extracted form the message queue.  If so, it stores the
event into C<$event_return> and returns true.  Else it returns false without
blocking.

There's also a variation that uses a callback to choose which message to extract
but that would be a pain to implement and probably not used much.

=head3 XSendEvent

  XSendEvent($display, $window, $propagate, $event_mask, $xevent)
    or die "Xlib hates us";

Send an XEvent.

=head3 XPutBackEvent

  XPutBackEvent($display, $xevent)

Push an XEvent back onto the queue.  This can also presumably put an
arbitrarily bogus event onto your own queue since it returns void.

=head3 XFlush

  XFlush($display)

Push any queued messages to the X11 server.  If you're wondering why nothing
happened when you called an XTest function, this is why.

=head3 XSync

  XSync($display);
  XSync($display, $discard);

Force a round trip to the server to process all pending messages and receive
the responses (or errors).  A true value for the second argument will wipe your
incoming event queue.

=head3 XSelectInput

  XSelectInput($display, $window, $event_mask)

Change the event mask for a window.

=head2 SCREEN FUNCTIONS

=head3 DisplayWidth

=head3 DisplayHeight

  my $w= DisplayWidth($display, $screen);
  my $h= DisplayHeight($display, $screen);

Return the width or height of screen number C<$screen>.  You can omit the
C<$screen> paramter to use the default screen of your L<Display> connection.

=head3 RootWindow

  my $xid= RootWindow($display, $screen)

Return the XID of the X11 root window.  C<$screen> is optional, and defaults to the
default screen of your connection.
If you want a Window object, call this method on L<X11::Xlib::Display>.

=head3 XMatchVisualInfo

  XMatchVisualInfo($display, $screen, $depth, $class, my $xvisualinfo_return)
    or die "Don't have one of those";

Loads the details of a L</Visual> into the final argument,
which must be an L</XVisualInfo> (or undefined, to create one)

Returns true if it found a matching visual.

=head3 XGetVisualInfo

  my @info_structs= XGetVisualInfo($display, $mask, $xvis_template);

Returns a list of L</XVisualInfo> each describing an available L</Visual>
which matches the template (also XVisualInfo) you provided.

C<$mask> can be one of:

  VisualIDMask
  VisualScreenMask
  VisualDepthMask
  VisualClassMask
  VisualRedMaskMask
  VisualGreenMaskMask
  VisualBlueMaskMask
  VisualColormapSizeMask
  VisualBitsPerRGBMask
  VisualAllMask

each describing a field of L<X11::Xlib::XVisualInfo> which is relevant
to your search.

=head3 XVisualIDFromVisual

  my $vis_id= XVisualIDFromVisual($visual);
  # or, assuming $visual is blessed,
  my $vis_id= $visual->id;

Pull the visual ID out of the opaque object $visual.

If what you wanted was actually the XVisualInfo for a C<$visual>, then try:

  my ($vis_info)= GetVisualInfo($display, VisualIDMask, { visualid => $vis_id });
  # or with Display object:
  $display->visual_by_id($vis_id);

=head3 DefaultVisual

  my $visual= DefaultVisual($display, $screen);

Screen is optional and defaults to the default screen of your connection.
This returns a L</Visual>, not a L</XVisualInfo>.

=head3 XCreateColormap

  my $xid= XCreateColormap($display, $rootwindow, $visual, $alloc_flag);
  # or 99% of the time
  my $xid= XCreateColormap($display, RootWindow($display), DefaultVisual($display), AllocNone);
  # and thus these are the defaults
  my $xid= XCreateColormap($display);

Create a L</Colormap>.  Why is this function in the "Screen" section and not
the "Window" section?  because it claims the only reason it wants the Window
is to determine the screen to create a map for. The C<$visual> is a L</Visual>
object, and the C<$alloc_flag> is either C<AllocNone> or C<AllocAll>.

=head2 XTEST INPUT SIMULATION

These methods create fake server-wide input events, useful for automated testing.
They are available through the XTEST extension.

Don't forget to call L</XFlush> after these methods, if you want the events to
happen immediately.

=head3 XTestFakeMotionEvent($display, $screen, $x, $y, $EventSendDelay)

Fake a mouse movement on screen number C<$screen> to position C<$x>,C<$y>.

The optional C<$EventSendDelay> parameter specifies the number of milliseconds to wait
before sending the event. The default is 10 milliseconds.

=head3 XTestFakeButtonEvent($display, $button, $pressed, $EventSendDelay)

Simulate an action on mouse button number C<$button>. C<$pressed> indicates whether
the button should be pressed (true) or released (false). 

The optional C<$EventSendDelay> parameter specifies the number of milliseconds ro wait
before sending the event. The default is 10 milliseconds.

=head3 XTestFakeKeyEvent($display, $kc, $pressed, $EventSendDelay)

Simulate a event on any key on the keyboard. C<$kc> is the key code (8 to 255),
and C<$pressed> indicates if the key was pressed or released.

The optional C<$EventSendDelay> parameter specifies the number of milliseconds to wait
before sending the event. The default is 10 milliseconds.

=head3 XBell($display, $percent)

Make the X server emit a sound.

=head3 XQueryKeymap($display)

Return a list of the key codes currently pressed on the keyboard.

=head2 KEYCODE FUNCTIONS

=head3 XKeysymToKeycode($display, $keysym)

Return the key code corresponding to the character number C<$keysym>.

=head3 XGetKeyboardMapping($display, $keycode, $count)

Return an array of character numbers corresponding to the key C<$keycode>.

Each value in the array corresponds to the action of a key modifier (Shift, Alt).

C<$count> is the number of the keycode to return. The default value is 1, e.g.
it returns the character corresponding to the given $keycode.

=head3 XKeysymToString($keysym)

Return the human-readable string for character number C<$keysym>.

C<XKeysymToString> is the exact reverse of C<XStringToKeysym>.

=head3 XStringToKeysym($string)

Return the keysym number for the human-readable character C<$string>.

C<XStringToKeysym> is the exact reverse of C<XKeysymToString>.

=head3 IsFunctionKey($keysym)

Return true if C<$keysym> is a function key (F1 .. F35)

=head3 IsKeypadKey($keysym)

Return true if C<$keysym> is on numeric keypad.

=head3 IsMiscFunctionKey($keysym)

Return true is key if... honestly don't know :\

=head3 IsModifierKey($keysym)

Return true if C<$keysym> is a modifier key (Shift, Alt).

=head3 IsPFKey($keysym)

No idea.

=head3 IsPrivateKeypadKey($keysym)

Again, no idea.

=cut

=head1 STRUCTURES

Xlib has a lot of C structs.  Most of them do not have much "depth"
(i.e. pointers to further nested structs) and so I chose to represent them
as simple blessed scalar refs to a byte string.  This gives you the ability
to pack new values into the struct which might not be known by this module,
and keeps the object relatively lightweight.  Most also have a C<pack> and
C<unpack> method which convert from/to a hashref.
Sometimes however these structs do contain a raw pointer value, and so you
should take extreme care if you do modify the bytes.

Xlib also has a lot of "opaque objects" where they just give you a pointer
and some methods to access it without any explanation of its inner fields.
I represent these with the matching Perl feature for blessed opaque references,
so the only way to interact with the pointer value is through XS code.
In each case, when the object goes out of scope, this library calls the
appropriate "Free" function.

Finally, there are lots of objects which exist on the server, and Xlib just
gives you a number (L</XID>) to refer to them when making future requests.
Windows are the most common example.  Since these are simple integers, and
can be shared among any program connected to the same display, this module
allows a mix of simple scalar values or blessed objects when calling any
function that expects an C<XID>.  The blessed objects derive from L<X11::Xlib::XID>.

Most supported structures have their own package with further documentation,
but here is a quick list:

=head2 Display

Represents a connection to an X11 server.  Xlib provides an B<opaque pointer>
C<Display*> on which you can call methods.  These are represented by this
package, C<X11::Xlib>.  The L<X11::Xlib::Display> package provides a more
perl-ish interface and some helper methods to "DWIM".

=head2 XEvent

A B<struct> that can hold any sort of message sent to/from the server.  The struct
is a union of many other structs, which you can read about in L<X11::Xlib::XEvent>.

=head2 Visual

An B<opaque pointer> describing binary representation of pixels for some mode of
the display.  There's probably only one in use on the entire display (i.e. RGBA)
but Xlib makes you look it up and pass it around to various functions.

=head2 XVisualInfo

A more useful B<struct> describing a Visual.  See L<X11::Xlib::XVisualInfo>.

=head2 Colormap

An B<XID> referencing what used to be a palette for 8-bit graphics but which is
now mostly a useless appendage to be passed to L</XCreateWindow>.

=head2 Window

An B<XID> referencing a Window.  See L<X11::Xlib::Window>.

=head1 SYSTEM DEPENDENCIES

Xlib libraries are found on most graphical Unixes, but you might lack the header
files needed for this module.  Try the following:

=over

=item Debian (Ubuntu, Mint)

sudo apt-get install libxtst-dev

=item Fedora

sudo yum install libXtst-devel

=back

=head1 SEE ALSO

=over 4

=item L<X11::GUITest>

This module provides the same functions but with a high level approach.

=item L<Gtk2>

Functions provided by X11/Xlib are mostly included in the L<Gtk2> binding, but
through the GTK API and perl objects.

=back

=head1 NOTES

This module is still incomplete, but patches are welcome :)

=head1 AUTHOR

Olivier Thauvin, E<lt>nanardon@nanardon.zarb.orgE<gt>

Michael Conrad, E<lt>mike@nrdvana.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009-2010 by Olivier Thauvin

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
