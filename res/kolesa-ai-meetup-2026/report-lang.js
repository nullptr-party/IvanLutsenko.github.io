/* Язык «report» для highlight.js: ключи отчёта crash-report («Crash:»,
   «Root cause:», «Fix before (HostActivity.kt):») в начале строки — attr.
   Подсветка идёт построчно, поэтому якорь ^ — начало строки отчёта. */
(() => {
  if (!window.hljs) return;
  window.hljs.registerLanguage('report', () => ({
    name: 'report',
    contains: [{ className: 'attr', begin: /^[A-Z][A-Za-z]+(?: [A-Za-z]+)*(?: \([^)]*\))?:(?=\s|$)/ }],
  }));
})();
