chrome.action.onClicked.addListener((tab) => {
  if (!tab.url) return;

  // جلوگیری از اجرا روی صفحات داخلی مرورگر
  if (
    tab.url.startsWith("chrome://") || 
    tab.url.startsWith("edge://") || 
    tab.url.startsWith("about:") || 
    tab.url.startsWith("moz-extension://")
  ) {
    return;
  }

  // بررسی اینکه آیا سایت مربوط به بیمه دانا یا کارآفرین است
  const isAllowed = tab.url.includes("dana-insurance.ir") || tab.url.includes("inssw.ir") || tab.url.startsWith("file://");

  if (!isAllowed) {
    chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => alert("این افزونه فقط در سامانه‌های آنلاین بیمه دانا و بیمه کارآفرین کار می‌کند.")
    });
    return;
  }

  // تزریق کد به "تمامی فریم‌ها" (allFrames: true) برای دور زدن مشکل تب‌های تو در تو
  chrome.scripting.executeScript({
    target: { tabId: tab.id, allFrames: true },
    files: ["content.js"]
  }).then((injectionResults) => {
    let extractedData = null;

    // بررسی نتیجه از تمام فریم‌ها برای پیدا کردن فریمی که حاوی جدول است
    for (const frameResult of injectionResults) {
      if (frameResult.result && frameResult.result.rows && frameResult.result.rows.length > 0) {
        extractedData = frameResult.result;
        break; 
      }
    }

    if (extractedData) {
      // اگر اطلاعات پیدا شد، ذخیره کن و صفحه پرینت را باز کن
      chrome.storage.local.set({ insuranceData: extractedData }, () => {
        const printUrl = chrome.runtime.getURL("print.html");
        
        chrome.tabs.query({ url: printUrl }, (tabs) => {
          if (tabs.length > 0) {
            const existingTab = tabs[0];
            chrome.tabs.reload(existingTab.id);
            chrome.tabs.update(existingTab.id, { active: true });
            chrome.windows.update(existingTab.windowId, { focused: true });
          } else {
            chrome.tabs.create({ url: printUrl });
          }
        });
      });
    } else {
      // اگر هیچ فریمی جدول را نداشت
      chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => alert("جدول اطلاعات یافت نشد. دقت کنید که لیست دورن یکی از تب‌ها باز باشد و صفحه کاملا لود شده باشد.")
      });
    }
  }).catch(err => console.error("Script injection failed:", err));
});
