/*
  Flow CRM site theme ("Gece mesaisi"). Loaded synchronously in <head> so the theme is
  set before the first paint. Dark is the default. A visitor's choice is remembered in
  localStorage; until they choose, the page follows prefers-color-scheme.
  Toggle buttons: <button data-theme-toggle data-label-light="…" data-label-dark="…">.
*/
(function () {
  "use strict";
  var KEY = "flow-crm-theme";
  var root = document.documentElement;
  var query = null;

  root.className += (root.className ? " " : "") + "js";

  try {
    query = window.matchMedia ? window.matchMedia("(prefers-color-scheme: light)") : null;
  } catch (e) {
    query = null;
  }

  function stored() {
    try {
      var value = window.localStorage.getItem(KEY);
      return value === "light" || value === "dark" ? value : null;
    } catch (e) {
      return null;
    }
  }

  function remember(theme) {
    try {
      window.localStorage.setItem(KEY, theme);
    } catch (e) {
      /* Storage blocked (private mode, disabled cookies): the choice lasts this page. */
    }
  }

  function system() {
    return query && query.matches ? "light" : "dark";
  }

  function current() {
    return root.getAttribute("data-theme") === "light" ? "light" : "dark";
  }

  function apply(theme) {
    root.setAttribute("data-theme", theme);
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", theme === "light" ? "#F4F5F0" : "#0E1116");
    var buttons = document.querySelectorAll("[data-theme-toggle]");
    for (var i = 0; i < buttons.length; i++) {
      var label = buttons[i].getAttribute(theme === "light" ? "data-label-dark" : "data-label-light");
      if (label) {
        buttons[i].setAttribute("aria-label", label);
        buttons[i].setAttribute("title", label);
      }
    }
  }

  apply(stored() || system());

  if (query) {
    var follow = function () {
      if (!stored()) apply(system());
    };
    try {
      if (query.addEventListener) query.addEventListener("change", follow);
      else if (query.addListener) query.addListener(follow);
    } catch (e) {
      /* Older browsers without change events keep the initial theme. */
    }
  }

  function bind() {
    var buttons = document.querySelectorAll("[data-theme-toggle]");
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].addEventListener("click", function () {
        var next = current() === "light" ? "dark" : "light";
        remember(next);
        apply(next);
      });
    }
    apply(current());
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", bind);
  else bind();
})();
