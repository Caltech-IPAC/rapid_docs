# Database backups: the pgBackRest repository

**Status: DRAFT.** One ruling is pending: what the WAL valve does when
archiving fails (Ben's, below). The rest records what was read on
2026-10-27 between 18:56 and 19:05 UTC.

The pipeline database's bookkeeping exists only in the database, and
its two backups are what protect it ([foundation](foundation)): a daily
EBS snapshot set of the data and WAL volumes, the newest 14 kept, and
pgBackRest's repository in S3, a base backup each day at 07:30 UTC
(full on Sundays, differential otherwise) and every WAL segment
archived as PostgreSQL closes it. This page is about the second. It
answers three questions about the repository, each against the
primary documentation for the version running, pgBackRest 2.60.0
(`pgbackrest version` on the database host, 18:56 UTC; the
documentation site gives v2.60.0 as the current stable release,
released October 18, 2026). The configuration read is rapid_systems
`rpms/rapid-db-tools/pgbackrest.conf.in` and the file rendered from
it on the host, which match.

## Bucket versioning

Until 2026-10-27 the repository's bucket was not versioned, so a
delete, whether pgBackRest's own expire, a mistake or a compromised
host, removed the bytes at once. pgBackRest 2.60 can read a repository
as it stood at an earlier time when the storage keeps versions
([configuration reference](https://pgbackrest.org/configuration.html),
Target Time for Repository): "This allows the command to read the
repository as it was at a point-in-time in order to recover data that
has been deleted or corrupted by user accident or malware. Versioned
storage is supported by S3 , GCS , and Azure but is generally not
enabled by default."

The bucket's lifecycle already expired objects under the repository
prefix after 90 days and under the clone-scratch prefix after 7, and
had no rule for the retained-release prefix. On a versioned bucket an
expiration does not delete
([S3 user guide, expiring objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-expire-general-considerations.html)):
"If the current object version is not a delete marker, Amazon S3 adds
a delete marker with a unique version ID. This makes the current
version noncurrent, and the delete marker the current version." The
bytes go only under a noncurrent rule, whose clock starts at the
delete: "You can base this expiration on a certain number of days
since the objects became noncurrent."

The two agree with the lifecycle as it stood, so rapid_systems PR 445
turned versioning on and gave each rule a noncurrent expiry equal to
its own backstop: 90 days for the repository, 7 for clone scratch. A
file pgBackRest expires stays recoverable for 90 days after the
delete. The retained-release prefix still has no rule, so an
overwritten or deleted copy there stays as a noncurrent version
indefinitely, which keeps that prefix's promise that nothing expires.
No separate rule removes delete markers, because both rules expire by
days
([S3 user guide, lifecycle examples](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-configuration-examples.html)):
"When you specify the Days tag, Amazon S3 automatically performs
ExpiredObjectDeleteMarker cleanup when the delete markers are old
enough to satisfy the age criteria." The host's role may delete
objects but not object versions, so it can make bytes noncurrent and
cannot destroy them.

A restore at an earlier repository time (`--repo-target-time`) needs a
role that can list and read versions, which the host's role cannot.
That grant belongs with the first drill that exercises it.

## The WAL valve

The configuration sets `archive-push-queue-max=64GiB` and leaves
`archive-async` off, so every WAL segment is pushed by PostgreSQL's
`archive_command` in turn. The question was whether the valve acts at
all without asynchronous archiving.

It does. The option's text
([command reference](https://pgbackrest.org/command.html), Maximum
Archive Push Queue Size) qualifies only its asynchronous details with
"In asynchronous mode", and the 2.59.0 release note that fixed its
enforcement measures the asynchronous queue "against all the WAL
PostgreSQL is waiting to archive, as in synchronous mode"
([release notes](https://pgbackrest.org/release.html), v2.59.0). What
it does past the cap, in the reference's words: "pgBackRest will
notify PostgreSQL that the WAL was successfully archived, then DROP IT
. A warning will be output to the PostgreSQL log. If this occurs then
the archive log stream will be interrupted and PITR will not be
possible past that point. A new backup will be required to regain full
restore capability." The reference gives the warning's level and not
its text. The queue is the WAL PostgreSQL has not yet archived, so
the valve opens when 64 GiB is waiting, about 72 % of the 100 GiB WAL
volume with the 8 GiB working set.

**What the alarms see.** `rapid-db-archiver-failing` pages after ten
consecutive minutes in which the archiver's most recent attempt
failed. Before any drop, archiving must fail long enough for 64 GiB to
queue: about an hour at the fastest fill measured (1 GiB a minute,
2026-08-09), and weeks at the repository's average of 1.3 GiB of WAL
a day (1,093 segments in 13.6 days). The page therefore always comes
at least 50 minutes before the first drop. Once drops begin, each
dropped segment counts in PostgreSQL as archived, so the most recent
attempt reads as a success and the alarm returns to OK, in our reading
within a minute or two (inferred from the metric's definition, not
observed). The alarm carries no OK action, so the earlier page stands,
but the console shows OK while recovery points are being lost.
`rapid-db-wal-40pct` stays in ALARM while the queue sits at the cap.
It sends nothing, by design (Ben, 2026-09-12). The WAL-full runbook
in rapid_systems (`docs/reference/wal-full-recovery-runbook.md`)
names the valve and treats it as working as designed, and it has no
step to take a backup once archiving resumes.

**The ruling owed (Ben's).** Two routes, the recommendation first.

Keep the valve. The database stays up through any archive outage. If
nobody fixes archiving within the hour after the page, recovery
points between the first dropped segment and the next backup are
lost. The backups before the gap still restore to the point before
it, and the next 07:30 UTC backup, if archiving has recovered by then,
re-establishes point-in-time recovery from there with no one
involved. What it needs: the runbook gains a step, after archiving
resumes, to take a full backup and check `pgbackrest info` shows it,
and the drop is made visible as itself, for example a count of the
pgBackRest warning in the database log.

Remove the valve. Archive failure fills the WAL volume and PostgreSQL
stops, about 90 minutes after the onset at the fastest fill, and
point-in-time recovery is never silently broken. The page at ten
minutes still comes first. A stopped database needs the WAL-full
runbook by hand, and its recovery itself moves segments off the
volume, which leaves the same gap unless they are archived afterwards.
The pipeline stops with the database until someone acts.

The recommendation is to keep the valve, with the runbook's backup
step and the drop made visible. The page always precedes a drop by
most of an hour. The loss is bounded to the gap and closed by the
next daily backup without a person, while removal turns an unattended
night into an outage whose own recovery risks the same gap. Nothing
was changed on 2026-10-27.

## Retention

The policy is `repo1-retention-full=4` with the retention type at its
default, count, and no archive retention set. The reference
([configuration reference](https://pgbackrest.org/configuration.html),
Archive Retention) says WAL then follows the fulls: "If this value is
not set and repo-retention-full-type is count (default), then the
archive to expire will default to the repo-retention-full ... value
... This will ensure that WAL is only expired for backups that are
already expired." Expire runs after each backup.

**What the policy retains.** With a full every Sunday, four fulls
span three weekly intervals. Just after a Sunday full has expired the
oldest, point-in-time recovery reaches back 21 days; just before the
next one, 28. Against the snapshot set's 14 days, the policy covers
more than either window at all times. Against the bucket's 90-day
backstop, the policy expires everything long before the backstop would
act, so at steady state the backstop never touches the repository.
The one window derived from this policy elsewhere, the garbage
collector's 21-day horizon floor (rapid_systems
`cloudformation/rapid-gc-params.yaml`), is the same arithmetic and is
met. rapid_systems `docs/architecture.md` calls the repository the
"90-day, point-in-time secondary"; 90 days is the bucket's backstop,
and point-in-time recovery reaches back 21 to 28 days. The policy
falls short of no window the documents promise, so
`repo1-retention-full` was not changed.

**What the repository holds now** (`pgbackrest info`, 18:56 UTC): four
fulls, `20261014-035125F`, `20261014-045555F`, `20261018-073050F` and
`20261025-073058F`, and twelve differentials, the newest
`20261025-073058F_20261027-073036D` stopped at 2026-10-27 07:31:58
UTC. The WAL archive runs from `00000001000000000000004C`, the
oldest full's start, to `000000010000000400000090`, which PostgreSQL
recorded as archived at 18:35:24 UTC, with no failed attempt since its
statistics reset on 2026-10-13. A listing of the archive at 19:00 UTC found all 1,093
segment names between the two, with none missing. The latest
evidenced recovery endpoint is therefore the end of segment
`000000010000000400000090`, archived 2026-10-27 18:35:24 UTC, and the
repository holds 13.6 days, from the oldest full's stop (2026-10-14
03:52:04 UTC) to that endpoint.

That is short of the snapshot set's 14 days and of the policy's 21,
and both shortfalls come from the repository's age, not from the
policy. The repository started afresh on 2026-10-13, and two fulls
taken by hand on 2026-10-14 used two of the four places, so the
2026-10-13 full expired on 2026-10-25. The repository passes 14 days
at 2026-10-28 03:52 UTC, and the 2026-11-08 full brings it to steady
state at 21 days.

**What is demonstrated recoverable.** The last restore on record is
the cutover drill of 2026-10-12 and 13, which restored full
`20261013-000300F` in 35 seconds. That backup has since expired, so no
backup now in the repository has been restored. The weekly `verify`
of 2026-10-26 09:00 UTC ended "completed successfully" with its output
set to none, which prints errors only
([command reference](https://pgbackrest.org/command.html), Repository
Verify: "Verify determines if the backups and archives in a repository
are valid."). It checked what the repository held then, and the WAL
archived since has not been re-read. Continuity of the WAL across the
range rests on the segment names being complete, which shows that
every segment is present but not that each is readable. The restore
drill on the database verification plan is what turns this into a
demonstrated number.
