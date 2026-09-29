(function () {
  "use strict";

  const resources = window.PCMirrorTranslations || {};
  const supportedLanguages = ["ko", "en", "ja"];
  const storageKey = "pc-to-tv-mirror-language";

  function mapLanguage(locale) {
    const value = String(locale || "").trim().toLowerCase();
    if (/^ko(?:-|$)/.test(value)) return "ko";
    if (/^ja(?:-|$)/.test(value)) return "ja";
    if (/^en(?:-|$)/.test(value)) return "en";
    return "en";
  }

  function detectLanguage() {
    try {
      const browserLanguages = Array.isArray(window.navigator.languages)
        ? window.navigator.languages
        : [];
      const preferred = browserLanguages.find((value) => typeof value === "string" && value.trim())
        || window.navigator.language
        || "";
      return mapLanguage(preferred);
    } catch (_) {
      return "en";
    }
  }

  function getInitialLanguage() {
    try {
      const saved = window.localStorage.getItem(storageKey);
      if (supportedLanguages.includes(saved)) return saved;
    } catch (_) {
      // Storage can be unavailable in private or restricted browsing contexts.
    }
    return detectLanguage();
  }

  function getValue(object, key) {
    return key.split(".").reduce((value, part) => value && value[part], object);
  }

  function translateKey(language, key) {
    const value = getValue(resources[language], key);
    if (typeof value === "string") return value;
    const fallback = getValue(resources.en, key);
    return typeof fallback === "string" ? fallback : null;
  }

  function applyLanguage(language) {
    const nextLanguage = supportedLanguages.includes(language) ? language : "en";
    document.documentElement.lang = nextLanguage;

    document.querySelectorAll("[data-i18n]").forEach((element) => {
      const value = translateKey(nextLanguage, element.getAttribute("data-i18n"));
      if (value !== null) element.textContent = value;
    });

    document.querySelectorAll("[data-i18n-attr]").forEach((element) => {
      element.getAttribute("data-i18n-attr").split(";").forEach((entry) => {
        const separator = entry.indexOf(":");
        if (separator < 1) return;
        const attribute = entry.slice(0, separator).trim();
        const key = entry.slice(separator + 1).trim();
        const value = translateKey(nextLanguage, key);
        if (attribute && value !== null) element.setAttribute(attribute, value);
      });
    });

    document.querySelectorAll("[data-language-option]").forEach((button) => {
      const selected = button.getAttribute("data-language-option") === nextLanguage;
      button.setAttribute("aria-pressed", selected ? "true" : "false");
      button.classList.toggle("is-active", selected);
    });
  }

  applyLanguage(getInitialLanguage());

  document.querySelectorAll("[data-language-option]").forEach((button) => {
    button.addEventListener("click", () => {
      const language = button.getAttribute("data-language-option");
      if (!supportedLanguages.includes(language)) return;
      applyLanguage(language);
      try {
        window.localStorage.setItem(storageKey, language);
      } catch (_) {
        // Keep the current page language even if persistence is unavailable.
      }
    });
  });
})();