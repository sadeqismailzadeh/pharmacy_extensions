(function() {
  const parsers = [
    {
      name: "Tamin (تامین اجتماعی)",
      matches: () => document.getElementById("ctl00_ContentPlaceHolder1_grdItems_DXMainTable") !== null,
      parse: parseTamin
    },
    {
      name: "IHIO (بیمه سلامت / خدمات درمانی)",
      matches: () => document.querySelector(".AvicoCMPTemplateTreeTable") !== null,
      parse: parseIhio
    },
    {
      name: "Esakhad (نیروهای مسلح)",
      matches: () => document.querySelector("p-table.operationTable") !== null,
      parse: parseEsakhad
    }
  ];

  let extractedData = null;
  let matchedSite = null;

  // پیدا کردن پارسر مناسب بر اساس المان‌های موجود در صفحه فعلی
  for (const parser of parsers) {
    if (parser.matches()) {
      extractedData = parser.parse();
      matchedSite = parser.name;
      break;
    }
  }

  // اگر هیچ ساختاری با سایت‌های تعریف شده مطابقت نداشت
  if (!extractedData) {
    alert("ساختار جدول داروها در این صفحه یافت نشد یا سایت پشتیبانی نمی‌شود.");
    return;
  }

  // ارسال داده‌ها برای چاپ
  if (extractedData.length > 0) {
    chrome.runtime.sendMessage({ action: "open_print_page", data: extractedData });
  } else {
    alert(`هیچ داده دارویی در سایت ${matchedSite} استخراج نشد.`);
  }

  // ==========================================
  // توابع استخراج
  // ==========================================

  function parseTamin() {
    const table = document.getElementById("ctl00_ContentPlaceHolder1_grdItems_DXMainTable");
    const rows = table.querySelectorAll("tr[id*='_DXDataRow']");
    const data = [];

    rows.forEach(row => {
      const cells = row.querySelectorAll("td.dxgv");
      if (cells.length >= 13) {
        const code = cells[1].innerText.trim();
        const name = cells[2].innerText.trim();
        const qty = parseInt(cells[3].innerText.trim(), 10) || 0;
        
        // ایندکس ۶: مجموع کل | ایندکس ۱۲: سهم بیمار
        const total = parseFloat(cells[6].innerText.trim().replace(/,/g, '')) || 0;
        const patientPaid = parseFloat(cells[12].innerText.trim().replace(/,/g, '')) || 0;
        
        // فرمول جدید: (مبلغ کل - سهم بیمار) تقسیم بر مبلغ کل * 100
        const officialPercent = total > 0 ? (((total - patientPaid) / total) * 100).toFixed(7) : "0.0000000";

        data.push({ code, name, qty, total, patientPaid, officialPercent });
      }
    });
    return data;
  }

  function parseIhio() {
    const data = [];
    // انتخاب سطرهای حاوی اطلاعات دارو (رد کردن سطر جمع کل که اتریبیوت iscombineddrug ندارد)
    const rows = document.querySelectorAll(".AvicoCMPTemplateTreeTable table tbody tr[avi-t='p'][iscombineddrug]");

    rows.forEach(row => {
      // استفاده از :scope > td برای جلوگیری از تداخل با جداول تو در تو
      const cells = row.querySelectorAll(":scope > td");
      if (cells.length < 8) return;

      // 1. کد دارو: اولویت با کد ژنریک (برای هماهنگی با تامین)، در غیر اینصورت کد ملی 16 رقمی
      let genericCode = row.getAttribute("genericcode");
      let nationalNumber = row.getAttribute("nationalnumber");
      
      let code = genericCode || nationalNumber || "";
      if (!code) {
        const codeSpan = cells[0].querySelector("span");
        code = codeSpan ? codeSpan.innerText.trim() : cells[0].innerText.trim();
      }

      // 2. نام دارو: ستون دوم
      const nameSpan = cells[1].querySelector("span");
      const name = nameSpan ? nameSpan.innerText.trim() : cells[1].innerText.trim();

      // 3. تعداد ارائه شده
      let qty = parseInt(cells[3].innerText.trim(), 10);
      if (isNaN(qty)) {
        qty = parseInt(cells[2].innerText.trim(), 10) || 0; 
      }

      // استخراج مبلغ کل و سهم بیمار
      let total = parseFloat(row.getAttribute("amount"));
      if (isNaN(total)) {
        total = parseFloat(cells[5].innerText.trim().replace(/,/g, '')) || 0;
      }

      let patientPaid = parseFloat(row.getAttribute("patientpayment"));
      if (isNaN(patientPaid)) {
        patientPaid = parseFloat(cells[6].innerText.trim().replace(/,/g, '')) || 0;
      }

      // فرمول جدید
      const officialPercent = total > 0 ? (((total - patientPaid) / total) * 100).toFixed(7) : "0.0000000";

      data.push({ code, name, qty, total, patientPaid, officialPercent });
    });
    
    return data;
  }

   function parseEsakhad() {
    const data = [];
    // انتخاب سطرهای جدول (بدون در نظر گرفتن tfoot و th)
    const rows = document.querySelectorAll("p-table.operationTable tbody.p-datatable-tbody > tr");

    rows.forEach(row => {
      // دریافت سلول‌های مستقیم همان سطر
      const cells = row.querySelectorAll(":scope > td");
      
      // اگر تعداد ستون‌ها کمتر از 11 باشد، یعنی سطر مربوط به داده‌های دارو نیست
      if (cells.length < 11) return;

      // 1. کد دارو (ستون دوم)
      const code = cells[1].innerText.trim();

      // 2. نام دارو (ستون سوم) - حذف سه نقطه اضافه در انتهای نام‌های طولانی
      let name = cells[2].innerText.trim();
      name = name.replace(/\s*\.\.\.$/, ''); 

      // 3. تعداد (اولویت با "تعداد ارائه" در ستون پنجم، سپس "تعداد تجویز" در ستون چهارم)
      let qty = parseInt(cells[4].innerText.trim(), 10);
      if (isNaN(qty)) {
        qty = parseInt(cells[3].innerText.trim(), 10) || 0;
      }

      // ایندکس ۱۰: مبلغ کل | ایندکس ۹: پرداختی بیمار
      const total = parseFloat(cells[10].innerText.trim().replace(/,/g, '')) || 0;
      const patientPaid = parseFloat(cells[9].innerText.trim().replace(/,/g, '')) || 0;

      // فرمول جدید
      const officialPercent = total > 0 ? (((total - patientPaid) / total) * 100).toFixed(7) : "0.0000000";

      data.push({ code, name, qty, total, patientPaid, officialPercent });
    });

    return data;
  }
})();
