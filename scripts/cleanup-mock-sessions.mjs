// Delete all mock/seed sessions created by the seed script
const CONVEX_URL = "https://wary-mockingbird-65.eu-west-1.convex.cloud";

const MOCK_SESSION_IDS = [
  // First seed run (all dated Feb 19, wrong dates)
  "j97csytvtvqa7tvdmm6a32fhg581exer",
  "j976m0kgq5ts4ysqwk10yj59qh81fxzk",
  "j978k4s86mwt3qtn740e0xzdes81fgfj",
  "j974y6ac1ghesb9jg6qdepz75x81ettr",
  "j97dcr5k7ckytgx31a3hn75rjd81fxwg",
  "j97ewrw55xyjkyhzhv4trd8dtd81egy6",
  "j972js5d9970365xwg9c7593yd81fmwk",
  "j971hkg70zw66xebbj8t9h8vt981e6br",
  "j97102fg4mb4r49ysxgjn9mg3581fkxs",
  "j97cp88p555fxp9t9w3k3m1k8d81f6kb",
  "j9792z2188pt0sf592z8nxghrn81ejkf",
  "j977a44tzy5p8dbhsk3adtp62181fwhb",
  // Second seed run (correct dates)
  "j979faes3jv39yz86mm4rtc52s81fxkf",
  "j974dgbxc9wya7awqa5bsjc4r981e4ya",
  "j97b6p63mg8wjapdmk0cpxyrts81fqgy",
  "j9705ved1mgcjbgbxc4mc7d8nh81fqed",
  "j977xmtjncj39zkx9w353jrbah81ee3n",
  "j978vth2mbbqqte9mrvx4v0ds981ey4r",
  "j970wad1kebk2vnhj3yr3b1gzd81f1jf",
  "j974ym8fakqda5e3f4bx9s107581f1qa",
  "j97c40zrkv3jhkqrg6th78p0md81f9aw",
  "j971btaa73gfe78dvn6w4n11hd81fd0g",
  "j973a9606gcsm8tkmay3bn7brd81fmjq",
  "j97bcw7afk4s9ra1v9k8h0gn9s81fzwy",
];

async function callMutation(name, args) {
  const res = await fetch(`${CONVEX_URL}/api/mutation`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path: name, args }),
  });
  const data = await res.json();
  if (data.status !== "success") throw new Error(`${name}: ${JSON.stringify(data)}`);
  return data.value;
}

async function main() {
  let deleted = 0;
  let failed = 0;
  for (const id of MOCK_SESSION_IDS) {
    try {
      await callMutation("sessions:deleteSession", { id });
      console.log(`✓ Deleted ${id}`);
      deleted++;
    } catch (e) {
      console.log(`✗ Failed ${id}: ${e.message}`);
      failed++;
    }
  }
  console.log(`\nDone: ${deleted} deleted, ${failed} failed/not found.`);
}

main().catch(console.error);
