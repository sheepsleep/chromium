// Copyright (c) 2009 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// -----------------------------------------------------------------------------
// NOTE: If you change this file you need to touch renderer_resources.grd to
// have your change take effect.
// -----------------------------------------------------------------------------

var chromium = chromium || {};
(function () {
  native function AttachEvent(eventName);
  native function DetachEvent(eventName);

  // Event object.  If opt_eventName is provided, this object represents
  // the unique instance of that named event, and dispatching an event
  // with that name will route through this object's listeners.
  //
  // Example:
  //   chromium.tabs.onTabChanged = new chromium.Event("tab-changed");
  //   chromium.tabs.onTabChanged.addListener(function(data) { alert(data); });
  //   chromium.Event.dispatch_("tab-changed", "hi");
  // will result in an alert dialog that says 'hi'.
  chromium.Event = function(opt_eventName) {
    this.eventName_ = opt_eventName;
    this.listeners_ = [];
  };

  // A map of event names to the event object that is registered to that name.
  chromium.Event.attached_ = {};

  // Dispatches a named event with the given JSON array, which is deserialized
  // before dispatch. The JSON array is the list of arguments that will be
  // sent with the event callback.
  chromium.Event.dispatchJSON_ = function(name, args) {
    if (chromium.Event.attached_[name]) {
      if (args) {
        args = goog.json.parse(args);
      }
      chromium.Event.attached_[name].dispatch.apply(
          chromium.Event.attached_[name], args);
    }
  };

  // Dispatches a named event with the given arguments, supplied as an array.
  chromium.Event.dispatch_ = function(name, args) {
    if (chromium.Event.attached_[name]) {
      chromium.Event.attached_[name].dispatch.apply(
          chromium.Event.attached_[name], args);
    }
  };

  // Registers a callback to be called when this event is dispatched.
  chromium.Event.prototype.addListener = function(cb) {
    this.listeners_.push(cb);
    if (this.listeners_.length == 1) {
      this.attach_();
    }
  };

  // Unregisters a callback.
  chromium.Event.prototype.removeListener = function(cb) {
    var idx = this.findListener_(cb);
    if (idx == -1) {
      return;
    }

    this.listeners_.splice(idx, 1);
    if (this.listeners_.length == 0) {
      this.detach_();
    }
  };

  // Test if the given callback is registered for this event.
  chromium.Event.prototype.hasListener = function(cb) {
    return this.findListeners_(cb) > -1;
  };

  // Returns the index of the given callback if registered, or -1 if not
  // found.
  chromium.Event.prototype.findListener_ = function(cb) {
    for (var i = 0; i < this.listeners_.length; i++) {
      if (this.listeners_[i] == cb) {
        return i;
      }
    }

    return -1;
  };

  // Dispatches this event object to all listeners, passing all supplied
  // arguments to this function each listener.
  chromium.Event.prototype.dispatch = function(varargs) {
    var args = Array.prototype.slice.call(arguments);
    for (var i = 0; i < this.listeners_.length; i++) {
      try {
        this.listeners_[i].apply(null, args);
      } catch (e) {
        console.error(e);
      }
    }
  };

  // Attaches this event object to its name.  Only one object can have a given
  // name.
  chromium.Event.prototype.attach_ = function() {
    AttachEvent(this.eventName_);
    if (!this.eventName_)
      return;

    if (chromium.Event.attached_[this.eventName_]) {
      throw new Error("chromium.Event '" + this.eventName_ +
                      "' is already attached.");
    }

    chromium.Event.attached_[this.eventName_] = this;
  };

  // Detaches this event object from its name.
  chromium.Event.prototype.detach_ = function() {
    DetachEvent(this.eventName_);
    if (!this.eventName_)
      return;

    if (!chromium.Event.attached_[this.eventName_]) {
      throw new Error("chromium.Event '" + this.eventName_ +
                      "' is not attached.");
    }

    delete chromium.Event.attached_[this.eventName_];
  };
})();
