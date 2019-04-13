/*
 * Copyright (c) 2019-2019 ranfdev
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA
 *
 * Authored by: ranfdev and contributors
 */
using Granite;
using Granite.Widgets;
using Gtk;


namespace raddiu {
  public class Player: Object {
    public bool playing  {get;set;default = false;}
    public Subprocess mpv;
    public RadioData current_radio {get;set;}
    public void toggle() {
      if (playing)
        pause();
      else 
        resume();
    }
    public void pause() {
      if (mpv is Subprocess) {
        mpv.force_exit();
        playing = false;
      }
    }
    public void resume() {
      play(current_radio);
    }
    public void play(RadioData data) {
      current_radio = data;

      if (playing)
        pause();

      string[] spawn_args = {"mpv", data.url};
      mpv = new Subprocess.newv(spawn_args, SubprocessFlags.NONE);

      playing = true;
    }
  }


  [DBus (name = "org.gnome.SettingsDaemon.MediaKeys")]
  interface GnomeMediaKeys: Object {
    public abstract void GrabMediaPlayerKeys(string application, uint32 time) throws Error;
    public abstract signal void MediaPlayerKeyPressed(string application, string key);
  }

  public class Raddiu : Granite.Application {
    public static Player player;
    public static Soup.Session soup;
    public static GLib.Settings settings;
    public static string cache;
    public static string _app_id = "com.github.ranfdev.raddiu";

    private CssProvider css_provider = new CssProvider();

    private GnomeMediaKeys media_keys;

    private Widgets.PlayingPanel playing_view;

    private Views.Countries countries;
    private Views.Top top;
    private Views.Results results;
    private Views.Recents recents;

    private Stack stack;

    public ApplicationWindow window;

    static construct {
      player = new Player();
      soup = new Soup.Session(); 
      settings = new GLib.Settings(_app_id);
      cache = Path.build_path(Path.DIR_SEPARATOR_S, Environment.get_user_cache_dir(), _app_id);
    }

    public Raddiu () {
      Object(
        application_id: "com.github.ranfdev.raddiu", 
        flags: ApplicationFlags.FLAGS_NONE
        );
    }
    private void handle_keypress(dynamic Object bus, string application, string key) {
    }
    protected override void activate () {

      // Init player
      player = new Player();

      // create cache folder if it doesn't exist
      File cache_folder = File.new_for_path(cache);

      if (!cache_folder.query_exists()) {
        cache_folder.make_directory_async.begin();
      }

      // Init dbus
      try {

        media_keys = Bus.get_proxy_sync(BusType.SESSION,"org.gnome.SettingsDaemon" , "/org/gnome/SettingsDaemon/MediaKeys", DBusProxyFlags.NONE, null);
        media_keys.MediaPlayerKeyPressed.connect((caller,app,key) => {
          if (key == "Play" || key == "Pause") {
            Raddiu.player.toggle();
          }
        });

      } catch (Error e) {
        warning ("MEDIA KEY ERROR: %s", e.message);
      }


      try {
        media_keys.GrabMediaPlayerKeys(application_id, (uint32)0);
      } catch (Error e) {
        warning ("MEDIA KEY ERROR: %s", e.message);
      }



      // Init styles
      css_provider.load_from_resource ("/com/github/ranfdev/raddiu/Application.css");
      Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(),css_provider,Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);


      // Init window
      window = new Gtk.ApplicationWindow (this);
      window.get_style_context().add_class("rounded");


      window.title = "raddiu";
      window.set_default_size (900, 640);

      stack = new Gtk.Stack();
      stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;

      countries = new Views.Countries();
      stack.add_titled(countries, "countries","Countries");

      top = new Views.Top();
      stack.add_titled(top, "top", "Top");

      results = new Views.Results();
      stack.add_titled(results, "results", "Results");

      recents = new Views.Recents();
      stack.add_titled(recents, "recents", "Recents");

      var stack_switcher = new Gtk.StackSwitcher();

      var panes = new Gtk.Box(Orientation.HORIZONTAL, 0);
      window.add(panes);


      // Notify user if mpv is not found
      var dialog = new Granite.MessageDialog.with_image_from_icon_name(
        "The program mpv is not installed", 
        "Raddiu to function needs to use the program mpv. Install it with your package manager (eg: 'sudo apt install mpv')",
        "dialog-error"
        );
      dialog.response.connect(() => {
        quit();
      });

      var mpv_path = GLib.Environment.find_program_in_path("mpv");

      print("MPV PATH: %s\n", mpv_path);
      if (mpv_path == null) {
        dialog.show();
        dialog.run();
      }

      // mpv section end

      panes.pack_start (stack,true,true,0);

      playing_view = new Widgets.PlayingPanel();
      playing_view.hexpand = false;
      playing_view.halign = Align.END;
      panes.pack_end (playing_view, false, false, 0);



      var header = new Gtk.HeaderBar();
      header.show_close_button = true;
      header.set_custom_title(stack_switcher);

      var search_entry = new Gtk.SearchEntry();
      header.pack_end(search_entry);
      search_entry.search_changed.connect(() => {
        if (search_entry.text.length > 0) {
          stack.visible_child_name = "results"; 
          results.query = search_entry.text;
          results.load_next();
        }
      });

      window.set_titlebar(header);
      window.show_all ();

      window.destroy.connect(() => {
        Raddiu.player.pause();
      });
      stack.visible_child = top;
      stack_switcher.stack = stack;
    }

    public static int main (string[] args) {
      print("ok");
      var app = new Raddiu ();
      return app.run (args);
    }
  }
}
