! Capture the inputs and outputs of WAVEWATCH III's W3SNL1, W3SBT1, W3SDB1, W3SDS4, W3SIN4, W3SPR4,
! W3SLN1 and WAVNU1, and of a whole W3SRCE call, at the state of a run. The program links WW3's
! own library, built unchanged at the pinned commit, and calls the routines as W3SRCE calls them
! (w3srcemd.F90:1258, :1319, :1337, :1236, :1074, :1219) and W3SRCE as W3WAVE calls it
! (w3wavemd.F90:2224), on the spectrum that ww3_shel wrote to a restart file:
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
                        kdcon, kdmn, snlc1, snls1, snls2, snls3, sbtc1, &
                        sdbc1, sdbc2, fdonly, dth, ecos, esin, ssdsbr, ssdsc, ssdsp, ssdsbm, &
                        ssdsdth, ssdsiso, ssdsbrfdf, satindices, satweights, cumulw, ssdscos, &
                        tha => th, dsip, &
                        sig2, dden, dden2, bbeta, zzalp, zz0rat, ttauwshelter, sswellf, &
                        ssinthp, aalpha, wwnmeanp, wwnmeanptail, fte, ftf, sstxftftail, sstxftwn, &
                        zzwnd, slnc1, fspm, fshf, dtmax, dtmin, xflt, xrel, facti1, facti2, facp, &
                        fachfa, ffxfa, ffxfm, ffxpm, zz0max
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
  use w3dispmd,   only: wavnu1, ewn1, ecg1, dsie, n1max
  use w3sln1md,   only: w3sln1
  use w3srcemd,   only: w3srce
  use w3snl1md,   only: w3snl1
  use w3sbt1md,   only: w3sbt1
  use w3sdb1md,   only: w3sdb1
  use w3src4md,   only: w3spr4, w3sds4, w3sin4, tabu_tauhf, dikcumul, iustar, ialpha, ilevtail, &
                        tauhft, tauhft2, delust, delalp, deltail, taut, deltauw, delu, &
                        itaumax, jumax, tauwmax
  use constants,  only: grav, dwat, dair, pi, tpi, rade, nu_air, kappa, fwtable, sizefwtable, &
                        delab, abmin, srce_direct
  use w3gdatmd,   only: dw => zb
  implicit none

  integer, parameter :: out = 30
  integer :: ik, isea, i
  real    :: depth, emean, fmean, fmean1, wnmean, amax, ustar, usdir, tauwx, tauwy, cd, z0, charn
  real    :: fmeanws, dlwmean, x, x2, cons
  logical :: lbreak
  logical, allocatable :: llws(:)
  real, allocatable :: a(:), wn(:), cg(:), snl(:), dnl(:), sbt(:), dbt(:), sdb(:), ddb(:)
  real, allocatable :: sds(:), dds(:), brlambda(:)
  real    :: whitecap(4)
  real    :: u10, u10dir, cd4, z04, charn4, tauwx4, tauwy4, tauwnx, tauwny, drat, fmeanws4, dlw4
  real    :: sin4c(28), ust4, usd4, e4, f4, f14, wn4, amax4
  real, allocatable :: wn2(:), sin4s(:), sin4d(:)
  logical, allocatable :: llws4(:), llwsp(:)
  real    :: spr4in(4), fhigh, ustl
  real, allocatable :: sln(:)
  ! W3SRCE's arguments: what W3WAVE passes for a sea point of ww3_ts1 (no ice, no currents, no
  ! reflection, no icebergs, ASF = 1), and what it returns.
  real, allocatable :: spec(:), vsio(:), vdio(:), alpha(:), wns(:), cgs(:)
  logical :: shaveio
  real    :: ust, ustd, fpi, dtdyn, fcut, dtg, tauwxs, tauwys, tauox, tauoy, tauwix, tauwiy, tauwnxs, &
             tauwnys, phiaw, charns, tws, phioc, whitecaps(4), d50, psic, bedform(3), phibbl, taubbl(2), &
             tauice(2), phice, tauocx, tauocy, wnmeans, icef, reflec(4)
  integer :: refled(6)
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
  ! W3SDS4 as W3SRCE calls it (w3srcemd.F90:1298), with USTAR and USDIR of the W3SPR4 call above
  ! (no wind); in the configuration of ww3_ts1 they reach S and D only through SSDSC(5) = 0.
  allocate (sds(nspec), dds(nspec), brlambda(nspec))
  whitecap = 0.
  call w3sds4(a, wn, cg, ustar, usdir, depth, dair, sds, dds, 1, 1, brlambda, whitecap, dlwmean)

  ! W3SIN4 as a time step of W3SRCE calls it (w3srcemd.F90:1236), after the means and the stress
  ! that the step's start computes (:1066-1127): W3SPR4 with the stress of the waves at zero, W3SIN4,
  ! W3SPR4 again. The wind is ww3_ts1's at the restart's time (ww3_shel.inp: 12 m/s from 180°,
  ! blowing towards 90° in WW3's direction), the stress of the previous step is not in the
  ! restart, so USTAR starts at W3SRCE's first value (:1067).
  allocate (wn2(nspec), sin4s(nspec), sin4d(nspec), llws4(nspec))
  do ik = 1, nk
    wn2(1+(ik-1)*nth:ik*nth) = wn(ik)
  end do
  u10 = 12.; u10dir = 0.5*pi; drat = dair/dwat
  ust4 = 0.001; usd4 = 0.; tauwx4 = 0.; tauwy4 = 0.; llws4 = .true.
  call w3spr4(a, cg, wn, e4, f4, f14, wn4, amax4, u10, u10dir, ust4, usd4, &
              tauwx4, tauwy4, cd4, z04, charn4, llws4, fmeanws4, dlw4)
  call w3sin4(a, cg, wn2, u10, ust4, drat, 0., u10dir, z04, cd4, tauwx4, tauwy4, tauwnx, tauwny, &
              sin4s, sin4d, llws4, 1, 1, brlambda)
  ! W3SPR4's inputs, the stress of W3SIN4 among them, and what it returns.
  spr4in = [u10, u10dir, tauwx4, tauwy4]
  allocate (llwsp(nspec)); llwsp = llws4
  call w3spr4(a, cg, wn, e4, f4, f14, wn4, amax4, u10, u10dir, ust4, usd4, &
              tauwx4, tauwy4, cd4, z04, charn4, llws4, fmeanws4, dlw4)
  ! W3SLN1 as the first pass of W3SRCE calls it, with the FHIGH that W3SRCE computes before its
  ! loop (w3srcemd.F90:1066-1071, :1219), the switch of ww3_ts1 having no FAGE there.
  ustl  = max(0.001, ust4)
  fhigh = max((ffxfm + 0.) * max(f14, fmeanws4), ffxpm / ustl)
  allocate (sln(nspec))
  call w3sln1(wn, fhigh, ustl, u10dir, sln)
  ! The inputs of the call below, before it overwrites the stress.
  sin4c = [u10, ust4, usd4, z04, drat, dth, bbeta, zzalp, zz0rat, ttauwshelter, &
                         sswellf(1), sswellf(2), sswellf(3), sswellf(4), sswellf(5), sswellf(6), &
                         sswellf(7), ssinthp, aalpha, delust, delalp, deltail, delab, abmin, &
                         grav, nu_air, kappa, tpi]
  call w3sin4(a, cg, wn2, u10, ust4, drat, 0., u10dir, z04, cd4, tauwx4, tauwy4, tauwnx, tauwny, &
              sin4s, sin4d, llws4, 1, 1, brlambda)

  ! W3SRCE on the restart's spectrum, as W3WAVE calls it (w3wavemd.F90:2224), with DTG = 60 s, a
  ! global step cut short as W3WAVE cuts it before an output time, so the source loop takes a few
  ! passes, and IT = 1, so that W3SRCE keeps what it integrated (:2095).
  allocate (spec(nspec), vsio(nspec), vdio(nspec), alpha(nk), wns(nk), cgs(nk))
  spec = a; wns = wn; cgs = cg; alpha = 0.
  ust = 0.; ustd = 0.; fpi = 0.; tauwxs = 0.; tauwys = 0.; charns = 0.; wnmeans = 0.
  icef = 0.; reflec = 0.; refled = 0; d50 = 0.; psic = 0.; bedform = 0.; taubbl = 0.; tauice = 0.
  dtg = 60.
  call w3srce(srce_direct, 1, isea, isea, 1, 1, 1, a, spec, vsio, vdio, shaveio, alpha, wns, cgs, 0., &
              depth, u10, u10dir, 0., ust, ustd, 0., 0., 0., 0., icef, 0., reflec, refled, 1., 1., 1., &
              1., 1., 0., fpi, dtdyn, fcut, dtg, tauwxs, tauwys, tauox, tauoy, tauwix, tauwiy, tauwnxs, &
              tauwnys, phiaw, charns, tws, phioc, whitecaps, d50, psic, bedform, phibbl, taubbl, tauice, &
              phice, tauocx, tauocy, wnmeans, dair, 1.)

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
  ! W3SDB1's constants from mod_def.ww3 (ww3_grid's &SDB1), FDONLY as 1 or 0.
  call put('sdbconst', [sdbc1, sdbc2, merge(1., 0., fdonly)])
  ! W3SDS4: its constants, the switches of the configuration the program covers, INSIN4's tables.
  call put('sds4const', [dth, ssdsbr, ssdsc(2), ssdsc(3), ssdsc(5), ssdsc(6), ssdsc(21), ssdsp, &
                         ssdsbm(0), ssdsbm(1), ssdsbm(2), ssdsbm(3), ssdsbm(4), ustar, usdir, &
                         dair, grav, dwat, 2.*pi**2.])
  call put('sds4case', [ssdsc(1), ssdsdth, real(ssdsbrfdf), ssdsc(8), ssdsc(11), real(ssdsiso)])
  ! IK1 = 1 without the switch IG1 (w3src4md.F90:2055), which ww3_ts1 does not have.
  call puti('sds4int', [size(satindices, 1), 1, dikcumul])
  call put('ECOS', ecos(1:nth)); call put('ESIN', esin(1:nth))
  call put('SATW', reshape(satweights, [size(satweights)]))
  call puti('SATI', reshape(satindices, [size(satindices)]))
  call put('CUMULW', reshape(cumulw, [size(cumulw)]))
  ! What INSIN4 made SATINDICES, SATWEIGHTS and CUMULW from (w3src4md.F90:1032-1048, 1136-1172).
  call put('insin4const', [ssdscos]); call put('TH', tha(1:nth)); call put('DSIP', dsip(1:nk))
  ! INSIN4's SDSNTH, a local there: the same expression (w3src4md.F90:1033), compiled by the same gfortran.
  call puti('insin4int', [min(nint(ssdsdth/(dth*rade)), nth/2-1)])
  call put('SDS', sds); call put('DDS', dds)
  ! W3SIN4: its constants (written above), its tables, and what it returns.
  call put('sin4const', sin4c)
  call puti('sin4int', [iustar, ialpha, ilevtail, sizefwtable])
  call put('SIG2', sig2(1:nspec)); call put('DDEN', dden(1:nk)); call put('DDEN2', dden2(1:nspec))
  call put('ECOS2', ecos(1:nspec)); call put('ESIN2', esin(1:nspec))
  call put('FWTABLE', fwtable(0:sizefwtable))
  call put('TAUHFT', reshape(tauhft, [size(tauhft)]))
  call put('TAUHFT2', reshape(tauhft2, [size(tauhft2)]))
  call put('SIN', sin4s); call put('DIN', sin4d)
  call put('LLWS', merge(1., 0., llws4))
  call put('TAUW', [tauwx4, tauwy4, tauwnx, tauwny])
  ! W3SPR4: its constants, CALC_USTAR's table, the inputs of its call and its outputs.
  call put('spr4const', [wwnmeanptail, wwnmeanp, fte, ftf, sstxftftail, sstxftwn, deltauw, delu, zzwnd, &
                         aalpha, tauwmax])
  call puti('spr4int', [itaumax, jumax])
  call put('TAUT', reshape(taut, [size(taut)]))
  ! The constants of INSIN4's tables TABU_STRESS (TAUT), TABU_TAUHF and TABU_TAUHF2 (SIGMAX = SIG(NK)).
  call put('tabuconst', [zz0max, sig(nk)])
  call put('SPR4IN', spr4in); call put('SPR4LL', merge(1., 0., llwsp))
  call put('SPR4OUT', [e4, f4, f14, wn4, amax4, ust4, z04, charn4, cd4, fmeanws4, dlw4])
  ! W3SLN1.
  call put('sln1const', [slnc1, fspm, fshf]); call put('SLN1IN', [fhigh, ustl, u10dir]); call put('SLN', sln)
  ! WAVNU1: DISTAB's tables, which WN and CG above came from.
  call put('DISP', [dsie]); call puti('dispint', [n1max])
  call put('EWN1', ewn1(0:n1max+1)); call put('ECG1', ecg1(0:n1max+1))
  ! W3SRCE: its constants, the wind and the step, and what it returns.
  call put('srceconst', [dtmax, xflt, xrel, dtmin, facti1, facti2, facp, ffxfa, ffxfm, ffxpm, fachfa, tpi, &
                         grav, tpiinv, dair, dwat])
  call put('snlconst', [kdcon, kdmn, snlc1, snls1, snls2, snls3])
  call put('SRCEIN', [u10, u10dir, dtg, 1.])
  call put('SRCE', spec)
  call put('SRCEOUT', [dtdyn, fcut, ust, ustd, tauwxs, tauwys, tauox, tauoy, tauwix, tauwiy, tauwnxs, tauwnys, &
                       phiaw, charns, tws, phioc, phibbl, tauocx, tauocy, wnmeans, whitecaps(3)])
  ! TABU_TAUHF's own table. INSIN4 calls it, then TABU_TAUHF2 writes TAUHFT again when TTAUWSHELTER > 0
  ! (w3src4md.F90:1021-1026), as in ww3_ts1, so the TAUHFT above is TABU_TAUHF2's. Called last, so that
  ! nothing above sees it.
  call tabu_tauhf(sig(nk))
  call put('TAUHFT1', reshape(tauhft, [size(tauhft)]))
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
