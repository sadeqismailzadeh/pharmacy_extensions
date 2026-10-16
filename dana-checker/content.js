(function() {
  const parseAmount = (text) => {
    if (!text) return 0;
    return parseFloat(text.replace(/,/g, '')) || 0;
  };

  // ۱. بررسی جدول بیمه دانا
  const danaRows = document.querySelectorAll("tr.gridRow");
  if (danaRows && danaRows.length > 0) {
    const data = [];
    danaRows.forEach(row => {
      const nameCell = row.querySelector("[id$='_td_NameBimeShode']");
      const nationalIdCell = row.querySelector("[id$='_td_CodeMeli']");
      const invoiceAmountCell = row.querySelector("[id$='_td_MablaghSoratHesab']");
      const firstInsurerShareCell = row.querySelector("[id$='_td_SahmBimegarAval']");
      
    // استخراج شماره ردیف از دومین سلول (td)
      const tdCells = row.querySelectorAll("td");
      const rowNumber = tdCells.length > 1 ? tdCells[1].innerText.trim() : "-";

    // فقط سطرهایی را اضافه کن که سلول‌های اصلی را دارند
      if (nameCell && invoiceAmountCell && firstInsurerShareCell) {
        const name = nameCell.innerText.trim();
        const nationalId = nationalIdCell ? nationalIdCell.innerText.trim() : "";
        const invoiceAmount = parseAmount(invoiceAmountCell.innerText);
        const firstInsurerShare = parseAmount(firstInsurerShareCell.innerText);
        
      // فرمول اختصاصی: قابل پرداخت = مبلغ صورتحساب - سهم بیمه‌گر اول + 727,000
        const constantFee = 727000;
        const payableAmount = invoiceAmount - firstInsurerShare + constantFee;

        data.push({
          rowNumber,
          name,
          nationalId,
          invoiceAmount,
          firstInsurerShare,
          payableAmount
        });
      }
    });
    return { insuranceType: "dana", rows: data };
  }

  // ۲. بررسی جدول بیمه کارآفرین (ag-grid)
  const agRows = document.querySelectorAll(".ag-center-cols-container .ag-row");
  if (agRows && agRows.length > 0) {
    const data = [];
    agRows.forEach(row => {
      const indexCell = row.querySelector("[col-id='index']");
      const nameCell = row.querySelector("[col-id='insuredPersonFullName']");
      const nationalIdCell = row.querySelector("[col-id='nationalCode']");
      const amountCell = row.querySelector("[col-id='estimateAmount']");
      const statusCell = row.querySelector("[col-id='statusText']");

      if (nameCell && amountCell) {
        const rowNumber = indexCell ? indexCell.innerText.trim() : "-";
        const name = nameCell.innerText.trim();
        const nationalId = nationalIdCell ? nationalIdCell.innerText.trim() : "";
        const estimateAmount = parseAmount(amountCell.innerText);
        const status = statusCell ? statusCell.innerText.trim() : "";

        // فرمول بیمه کارآفرین: قابل پرداخت = (10 / 9) * مبلغ معرفی نامه
        const payableAmount = Math.round((10 / 9) * estimateAmount);

        data.push({
          rowNumber,
          name,
          nationalId,
          invoiceAmount: estimateAmount,
          payableAmount,
          status
        });
      }
    });
    return { insuranceType: "karafarin", rows: data };
  }

  return null;
})();
