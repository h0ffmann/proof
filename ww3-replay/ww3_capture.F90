! Capture the inputs and outputs of WAVEWATCH III's W3SNL1, W3SBT1 and W3SDB1 at the state of a
! run. The program links WW3's own library, built unchanged at the pinned commit, and calls the
! routines as W3SRCE calls them (w3srcemd.F90:1258, :1319, :1337), on the spectrum that ww3_shel
! wrote to a restart file:
!
!     ww3_capture YYYYMMDD HHMMSS ISEA
!
! It reads mod_def.ww3 and restart.ww3 from the current directory, as
! ww3_uprstr does (ww3_uprstr.F90:396-520), and writes capture.txt: one "name n" line, then n
! values, each REAL with nine significant digits, so that it reads back to the same float32.
!
! W3IOGR calls INSNL1 when it reads (w3iogrmd.F90:1381), so the DIA tables are WW3's own.
program ww3_capture
  use constants,  only: tpiinv
  use w3gdatmd,   only: w3nmod, w3setg, nk, nth, nspec, nsea, sig, dmin, fachfe, &
                        kdcon, kdmn, snlc1, snls1, snls2, snls3, sbtc1
  use w3wdatmd,   only: w3ndat, w3setw, va, time
  use w3adatmd,   only: w3naux, w3seta, nfr, nfrhgh, nfrchg, nspecx, nspecy, &
                        ip11, ip12, ip13, ip14, im11, im12, im13, im14,      &
                        ip21, ip22, ip23, ip24, im21, im22, im23, im24,      &
                        ic11, ic12, ic21, ic22, ic31, ic32, ic41, ic42,      &
                        ic51, ic52, ic61, ic62, ic71, ic72, ic81, ic82,      &
                        dal1, dal2, dal3, af11,                              &
                        awg1, awg2, awg3, awg4, awg5, awg6, awg7, awg8,      &
                        swg1, swg2, swg3, swg4, swg5, swg6, swg7, swg8
  use w3odatmd,   only: w3nout, w3seto, ndse, ndso, ndst, iaproc, napout, naperr, naplog, nds
  use w3idatmd,   only: w3ninp, w3seti
  use w3servmd,   only: itrace
  use w3iogrmd,   only: w3iogr
  use w3iorsmd,   only: w3iors
  use w3dispmd,   only: wavnu1
  use w3snl1md,   only: w3snl1
  use w3sbt1md,   only: w3sbt1
  use w3sdb1md,   only: w3sdb1
  use w3src4md,   only: w3spr4
  use w3gdatmd,   only: dw => zb
  implicit none

  integer, parameter :: out = 30
  integer :: ik, isea, i
  real    :: depth, emean, fmean, fmean1, wnmean, amax, ustar, usdir, tauwx, tauwy, cd, z0, charn
  real    :: fmeanws, dlwmean, x, x2, cons
  logical :: lbreak
  logical, allocatable :: llws(:)
  real, allocatable :: a(:), wn(:), cg(:), snl(:), dnl(:), sbt(:), dbt(:), sdb(:), ddb(:)
  character(len=16) :: arg

  call w3nmod(1, 6, 6); call w3setg(1, 6, 6)
  call w3ndat(6, 6);    call w3setw(1, 6, 6)
  call w3naux(6, 6);    call w3seta(1, 6, 6)
  call w3nout(6, 6);    call w3seto(1, 6, 6)
  call w3ninp(6, 6);    call w3seti(1, 6, 6)
  ndse = 6; ndso = 6; ndst = 6
  iaproc = 1; napout = 1; naperr = 1; naplog = 1
  call itrace(6, 10)
  call w3iogr('READ', 20)
  ! The arguments: the time of the restart (YYYYMMDD HHMMSS, which W3IORS checks) and the sea point.
  call get_command_argument(1, arg); read (arg, *) time(1)
  call get_command_argument(2, arg); read (arg, *) time(2)
  call get_command_argument(3, arg); read (arg, *) isea
  call w3iors('READ', nds(6), sig(nk), 1)
  ! The depth of the sea point with no water level, as W3INIT and W3WAVE set it
  ! (w3initmd.F90:1294, w3wavemd.F90:949).
  depth = max(dmin, max(0., -dw(isea)))

  allocate (a(nspec), wn(nk), cg(nk), snl(nspec), dnl(nspec), sbt(nspec), dbt(nspec), sdb(nspec), ddb(nspec))
  a = va(:, isea)
  do ik = 1, nk
    call wavnu1(sig(ik), depth, wn(ik), cg(ik))
  end do

  ! The means W3SRCE takes from W3SPR4 (w3srcemd.F90:1074); the wind does not enter EMEAN,
  ! FMEAN or WNMEAN.
  allocate (llws(nspec)); llws = .true.
  ustar = 0.; usdir = 0.; tauwx = 0.; tauwy = 0.
  call w3spr4(a, cg, wn, emean, fmean, fmean1, wnmean, amax, 0., 0., ustar, usdir, &
              tauwx, tauwy, cd, z0, charn, llws, fmeanws, dlwmean)

  call w3snl1(a, cg, wnmean*depth, snl, dnl)
  call w3sbt1(a, cg, wn, depth, sbt, dbt)
  call w3sdb1(1, a, depth, emean, fmean, wnmean, cg, lbreak, sdb, ddb)

  ! CONS of W3SNL1 (w3snl1md.F90:324-326), which the kernels take as data.
  x    = max(kdcon*wnmean*depth, kdmn)
  x2   = max(-1.e15, snls3*x)
  cons = snlc1 * (1. + snls1/x * (1.-snls2*x) * exp(x2))

  open (out, file='capture.txt', status='replace', action='write')
  write (out, '(a, 9i8)') 'dims', nth, nk, nspec, nfr, nfrhgh, nfrchg, nspecx, nspecy, isea
  call put('scalars', [depth, emean, fmean, wnmean, tpiinv, fachfe, cons, dal1, dal2, dal3, sbtc1])
  call put('awg', [awg1, awg2, awg3, awg4, awg5, awg6, awg7, awg8])
  call put('swg', [swg1, swg2, swg3, swg4, swg5, swg6, swg7, swg8])
  call put('A', a); call put('sig', sig(1:nk)); call put('wn', wn); call put('cg', cg)
  call put('af11', af11(1:nspecx))
  call puti('ip', [ip11(1:nspecx), ip12(1:nspecx), ip13(1:nspecx), ip14(1:nspecx), &
                   im11(1:nspecx), im12(1:nspecx), im13(1:nspecx), im14(1:nspecx), &
                   ip21(1:nspecx), ip22(1:nspecx), ip23(1:nspecx), ip24(1:nspecx), &
                   im21(1:nspecx), im22(1:nspecx), im23(1:nspecx), im24(1:nspecx)])
  call puti('ic', [ic11(1:nspec), ic12(1:nspec), ic21(1:nspec), ic22(1:nspec), &
                   ic31(1:nspec), ic32(1:nspec), ic41(1:nspec), ic42(1:nspec), &
                   ic51(1:nspec), ic52(1:nspec), ic61(1:nspec), ic62(1:nspec), &
                   ic71(1:nspec), ic72(1:nspec), ic81(1:nspec), ic82(1:nspec)])
  call put('SNL', snl); call put('DNL', dnl)
  call put('SBT', sbt); call put('DBT', dbt)
  call put('SDB', sdb); call put('DDB', ddb)
  close (out)
  write (*, '(a, i0, a, es12.4, a, l1)') 'ww3_capture: sea point ', isea, ', depth ', depth, ', lbreak ', lbreak

contains

  subroutine put(name, v)
    character(len=*), intent(in) :: name
    real, intent(in) :: v(:)
    write (out, '(a, 1x, i0)') name, size(v)
    write (out, '(es17.9e3)') (v(i), i = 1, size(v))
  end subroutine put

  subroutine puti(name, v)
    character(len=*), intent(in) :: name
    integer, intent(in) :: v(:)
    write (out, '(a, 1x, i0)') name, size(v)
    write (out, '(i0)') (v(i), i = 1, size(v))
  end subroutine puti

end program ww3_capture
