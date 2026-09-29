
(function () {
  const cfg = window.PCMIRROR_CONFIG || {};
  document.querySelectorAll("[data-download='windows']").forEach(a => {
    a.href = cfg.windowsDownloadUrl || "#";
  });
  document.querySelectorAll("[data-download='tv']").forEach(a => {
    a.href = cfg.tvDownloadUrl || "#";
  });
  document.querySelectorAll("[data-support-email]").forEach(a => {
    const email = cfg.supportEmail || "jihun@thj-project.info";
    a.textContent = email;
    a.href = "mailto:" + email;
  });
  document.querySelectorAll("[data-year]").forEach(n => n.textContent = new Date().getFullYear());
})();
