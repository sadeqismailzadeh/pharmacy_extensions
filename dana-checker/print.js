document.addEventListener("DOMContentLoaded", () => {
  chrome.storage.local.get("insuranceData", (result) => {
    const data = result.insuranceData;
    if (!data) return;

    const reportTitle = document.getElementById("reportTitle");
    const formulaNote = document.getElementById("formulaNote");
    const headerRow = document.getElementById("tableHeaderRow");
    const tbody = document.querySelector("#resultTable tbody");

    tbody.innerHTML = '';
    headerRow.innerHTML = '';

    if (data.insuranceType === "karafarin") {
      reportTitle.textContent = "گزارش لیست بیماران و مبالغ قابل پرداخت (بیمه کارآفرین)";
      formulaNote.innerHTML = `
        <strong>فرمول محاسبه:</strong>
        <div class="formula-container">
          <span>مبلغ قابل پرداخت</span>
          <span>=</span>
          <span>مبلغ معرفی‌نامه</span>
          <span>×</span>
          <span>(۱۰ / ۹)</span>
        </div>
      `;

      headerRow.innerHTML = `
        <th>ردیف</th>
        <th>نام بیمه شده</th>
        <th>کد ملی</th>
        <th>مبلغ قابل پرداخت (ریال)</th>
      `;

      data.rows.forEach(item => {
        const row = document.createElement("tr");
        row.innerHTML = `
          <td>${item.rowNumber}</td>
          <td>${item.name}</td>
          <td>${item.nationalId}</td>
          <td class="highlight-col">${formatNumber(item.payableAmount)}</td>
        `;
        tbody.appendChild(row);
      });

    } else {
      // حالت بیمه دانا
      reportTitle.textContent = "گزارش لیست بیماران و مبالغ قابل پرداخت (بیمه دانا)";
      formulaNote.innerHTML = `
        <strong>فرمول محاسبه:</strong>
        <div class="formula-container">
          <span>مبلغ قابل پرداخت</span>
          <span>=</span>
          <span>(</span>
          <span>مبلغ صورتحساب</span>
          <span>-</span>
          <span>سهم بیمه‌گر اول</span>
          <span>)</span>
          <span>+</span>
          <span>۷۲۷,۰۰۰ ریال</span>
        </div>
      `;

      headerRow.innerHTML = `
        <th>ردیف</th>
        <th>نام بیمه شده</th>
        <th>کد ملی</th>
        <th>مبلغ قابل پرداخت (ریال)</th>
      `;

      data.rows.forEach(item => {
        const row = document.createElement("tr");
        row.innerHTML = `
          <td>${item.rowNumber}</td>
          <td>${item.name}</td>
          <td>${item.nationalId}</td>
          <td class="highlight-col">${formatNumber(item.payableAmount)}</td>
        `;
        tbody.appendChild(row);
      });
    }
  });
});

// تابع جداکننده هزارگان اعداد
function formatNumber(num) {
  return num.toLocaleString('en-US');
}
