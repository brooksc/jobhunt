// Pure sort helpers extracted from jobs.jsx so they can be unit-tested.

export function sortValue(job, key) {
  if (key === "salaryMin") return job.salaryMin || job.salaryMax || null;
  if (key === "salaryMax") return job.salaryMax || job.salaryMin || null;
  if (key === "rating") return job.rating || null;
  if (key === "fitScore") return job.fit?.score ?? null;
  if (key === "extractionStatus") return job.extraction?.status || "";
  if (key === "lastProcessedAt") return job.extraction?.at || "";
  if (key === "lastOpenedAt") return job.lastOpenedAt || "";
  if (key === "lastStatusChangedAt") return job.lastStatusChangedAt || "";
  if (key === "nextActionDue") return job.nextAction?.dueDate || "";
  return job[key] ?? "";
}

export function sortJobs(jobs, sort) {
  const arr = [...jobs];
  arr.sort((a, b) => {
    const av = sortValue(a, sort.key);
    const bv = sortValue(b, sort.key);
    const aEmpty = av == null || av === "" || av === "—";
    const bEmpty = bv == null || bv === "" || bv === "—";
    if (aEmpty && bEmpty) return 0;
    if (aEmpty) return 1;
    if (bEmpty) return -1;
    const cmp = typeof av === "number" && typeof bv === "number"
      ? av - bv
      : String(av).localeCompare(String(bv), undefined, { numeric: true, sensitivity: "base" });
    return sort.dir === "asc" ? cmp : -cmp;
  });
  return arr;
}
