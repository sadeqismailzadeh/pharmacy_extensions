document.addEventListener("DOMContentLoaded", () => {
  chrome.storage.local.get("prescriptionData", (result) => {
    const data = result.prescriptionData;
    if (!data) return;

    const tbody = document.querySelector("#resultTable tbody");
    
    // پاک کردن اطلاعات قبلی جدول (برای جلوگیری از تکرار هنگام رفرش)
    tbody.innerHTML = '';

    let sumTotal = 0;
    let sumPatientPaid = 0; // تغییر یافته به سهم بیمار

    data.forEach(item => {
      sumTotal += item.total;
      sumPatientPaid += item.patientPaid; // جمع سهم بیمار

      const row = document.createElement("tr");
      row.innerHTML = `
        <td>${item.code}</td>
        <td>${item.name}</td>
        <td>${item.qty}</td>
        <td>${formatNumber(item.total)}</td>
        <td>${formatNumber(item.patientPaid)}</td>
        <td style="font-weight: bold; color: #0056b3; font-size: 14px;">${item.officialPercent}%</td>
      `;
      tbody.appendChild(row);
    });

    // فرمول جدید برای محاسبه درصد جمع کل فاکتور
    const finalOfficialPercent = sumTotal > 0 ? (((sumTotal - sumPatientPaid) / sumTotal) * 100).toFixed(7) : "0.0000000";

    const totalRow = document.createElement("tr");
    totalRow.className = "total-row";
    totalRow.innerHTML = `
      <td colspan="3">جمع کل اقلام</td>
      <td>${formatNumber(sumTotal)}</td>
      <td>${formatNumber(sumPatientPaid)}</td>
      <td style="font-weight: bold; color: #0056b3; font-size: 14px;">${finalOfficialPercent}%</td>
    `;
    tbody.appendChild(totalRow);
  });
});

function formatNumber(num) {
  return num.toLocaleString('en-US');
}