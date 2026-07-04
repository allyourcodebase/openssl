

.section	.ctors
	.p2align	3
	.quad	OPENSSL_cpuid_setup


.comm	OPENSSL_ia32cap_P,16,4

.text	

.globl	OPENSSL_atomic_add
.def	OPENSSL_atomic_add;	.scl 2;	.type 32;	.endef
.p2align	4
OPENSSL_atomic_add:

.byte	243,15,30,250
	movl	(%rcx),%eax
.Lspin:	leaq	(%rdx,%rax,1),%r8
.byte	0xf0
	cmpxchgl	%r8d,(%rcx)
	jne	.Lspin
	movl	%r8d,%eax
.byte	0x48,0x98
	.byte	0xf3,0xc3



.globl	OPENSSL_rdtsc
.def	OPENSSL_rdtsc;	.scl 2;	.type 32;	.endef
.p2align	4
OPENSSL_rdtsc:

.byte	243,15,30,250
	rdtsc
	shlq	$32,%rdx
	orq	%rdx,%rax
	.byte	0xf3,0xc3



.globl	OPENSSL_ia32_cpuid
.def	OPENSSL_ia32_cpuid;	.scl 2;	.type 32;	.endef
.p2align	4
OPENSSL_ia32_cpuid:
	movq	%rdi,8(%rsp)
	movq	%rsi,16(%rsp)
	movq	%rsp,%rax
.LSEH_begin_OPENSSL_ia32_cpuid:
	movq	%rcx,%rdi


.byte	243,15,30,250
	movq	%rbx,%r8


	xorl	%eax,%eax
	movq	%rax,8(%rdi)
	cpuid
	movl	%eax,%r11d

	xorl	%eax,%eax
	cmpl	$0x756e6547,%ebx
	setne	%al
	movl	%eax,%r9d
	cmpl	$0x49656e69,%edx
	setne	%al
	orl	%eax,%r9d
	cmpl	$0x6c65746e,%ecx
	setne	%al
	orl	%eax,%r9d
	jz	.Lintel

	cmpl	$0x68747541,%ebx
	setne	%al
	movl	%eax,%r10d
	cmpl	$0x69746E65,%edx
	setne	%al
	orl	%eax,%r10d
	cmpl	$0x444D4163,%ecx
	setne	%al
	orl	%eax,%r10d
	jnz	.Lintel


	movl	$0x80000000,%eax
	cpuid
	cmpl	$0x80000001,%eax
	jb	.Lintel
	movl	%eax,%r10d
	movl	$0x80000001,%eax
	cpuid
	orl	%ecx,%r9d
	andl	$0x00000801,%r9d

	cmpl	$0x80000008,%r10d
	jb	.Lintel

	movl	$0x80000008,%eax
	cpuid
	movzbq	%cl,%r10
	incq	%r10

	movl	$1,%eax
	cpuid
	btl	$28,%edx
	jnc	.Lgeneric
	shrl	$16,%ebx
	cmpb	%r10b,%bl
	ja	.Lgeneric
	andl	$0xefffffff,%edx
	jmp	.Lgeneric

.Lintel:
	cmpl	$4,%r11d
	movl	$-1,%r10d
	jb	.Lnocacheinfo

	movl	$4,%eax
	movl	$0,%ecx
	cpuid
	movl	%eax,%r10d
	shrl	$14,%r10d
	andl	$0xfff,%r10d

.Lnocacheinfo:
	movl	$1,%eax
	cpuid
	movd	%eax,%xmm0
	andl	$0xbfefffff,%edx
	cmpl	$0,%r9d
	jne	.Lnotintel
	orl	$0x40000000,%edx
	andb	$15,%ah
	cmpb	$15,%ah
	jne	.LnotP4
	orl	$0x00100000,%edx
.LnotP4:
	cmpb	$6,%ah
	jne	.Lnotintel
	andl	$0x0fff0ff0,%eax
	cmpl	$0x00050670,%eax
	je	.Lknights
	cmpl	$0x00080650,%eax
	jne	.Lnotintel
.Lknights:
	andl	$0xfbffffff,%ecx

.Lnotintel:
	btl	$28,%edx
	jnc	.Lgeneric
	andl	$0xefffffff,%edx
	cmpl	$0,%r10d
	je	.Lgeneric

	orl	$0x10000000,%edx
	shrl	$16,%ebx
	cmpb	$1,%bl
	ja	.Lgeneric
	andl	$0xefffffff,%edx
.Lgeneric:
	andl	$0x00000800,%r9d
	andl	$0xfffff7ff,%ecx
	orl	%ecx,%r9d

	movl	%edx,%r10d

	cmpl	$7,%r11d
	jb	.Lno_extended_info
	movl	$7,%eax
	xorl	%ecx,%ecx
	cpuid
	btl	$26,%r9d
	jc	.Lnotknights
	andl	$0xfff7ffff,%ebx
.Lnotknights:
	movd	%xmm0,%eax
	andl	$0x0fff0ff0,%eax
	cmpl	$0x00050650,%eax
	jne	.Lnotskylakex
	andl	$0xfffeffff,%ebx

.Lnotskylakex:
	movl	%ebx,8(%rdi)
	movl	%ecx,12(%rdi)
.Lno_extended_info:

	btl	$27,%r9d
	jnc	.Lclear_avx
	xorl	%ecx,%ecx
.byte	0x0f,0x01,0xd0
	andl	$0xe6,%eax
	cmpl	$0xe6,%eax
	je	.Ldone
	andl	$0x3fdeffff,8(%rdi)




	andl	$6,%eax
	cmpl	$6,%eax
	je	.Ldone
.Lclear_avx:
	movl	$0xefffe7ff,%eax
	andl	%eax,%r9d
	movl	$0x3fdeffdf,%eax
	andl	%eax,8(%rdi)
.Ldone:
	shlq	$32,%r9
	movl	%r10d,%eax
	movq	%r8,%rbx

	orq	%r9,%rax
	movq	8(%rsp),%rdi
	movq	16(%rsp),%rsi
	.byte	0xf3,0xc3

.LSEH_end_OPENSSL_ia32_cpuid:

.globl	OPENSSL_cleanse
.def	OPENSSL_cleanse;	.scl 2;	.type 32;	.endef
.p2align	4
OPENSSL_cleanse:

.byte	243,15,30,250
	xorq	%rax,%rax
	cmpq	$15,%rdx
	jae	.Lot
	cmpq	$0,%rdx
	je	.Lret
.Little:
	movb	%al,(%rcx)
	subq	$1,%rdx
	leaq	1(%rcx),%rcx
	jnz	.Little
.Lret:
	.byte	0xf3,0xc3
.p2align	4
.Lot:
	testq	$7,%rcx
	jz	.Laligned
	movb	%al,(%rcx)
	leaq	-1(%rdx),%rdx
	leaq	1(%rcx),%rcx
	jmp	.Lot
.Laligned:
	movq	%rax,(%rcx)
	leaq	-8(%rdx),%rdx
	testq	$-8,%rdx
	leaq	8(%rcx),%rcx
	jnz	.Laligned
	cmpq	$0,%rdx
	jne	.Little
	.byte	0xf3,0xc3



.globl	CRYPTO_memcmp
.def	CRYPTO_memcmp;	.scl 2;	.type 32;	.endef
.p2align	4
CRYPTO_memcmp:

.byte	243,15,30,250
	xorq	%rax,%rax
	xorq	%r10,%r10
	cmpq	$0,%r8
	je	.Lno_data
	cmpq	$16,%r8
	jne	.Loop_cmp
	movq	(%rcx),%r10
	movq	8(%rcx),%r11
	movq	$1,%r8
	xorq	(%rdx),%r10
	xorq	8(%rdx),%r11
	orq	%r11,%r10
	cmovnzq	%r8,%rax
	.byte	0xf3,0xc3

.p2align	4
.Loop_cmp:
	movb	(%rcx),%r10b
	leaq	1(%rcx),%rcx
	xorb	(%rdx),%r10b
	leaq	1(%rdx),%rdx
	orb	%r10b,%al
	decq	%r8
	jnz	.Loop_cmp
	negq	%rax
	shrq	$63,%rax
.Lno_data:
	.byte	0xf3,0xc3


.globl	OPENSSL_wipe_cpu
.def	OPENSSL_wipe_cpu;	.scl 2;	.type 32;	.endef
.p2align	4
OPENSSL_wipe_cpu:
	pxor	%xmm0,%xmm0
	pxor	%xmm1,%xmm1
	pxor	%xmm2,%xmm2
	pxor	%xmm3,%xmm3
	pxor	%xmm4,%xmm4
	pxor	%xmm5,%xmm5
	xorq	%rcx,%rcx
	xorq	%rdx,%rdx
	xorq	%r8,%r8
	xorq	%r9,%r9
	xorq	%r10,%r10
	xorq	%r11,%r11
	leaq	8(%rsp),%rax
	.byte	0xf3,0xc3

.globl	OPENSSL_instrument_bus
.def	OPENSSL_instrument_bus;	.scl 2;	.type 32;	.endef
.p2align	4
OPENSSL_instrument_bus:

.byte	243,15,30,250
	movq	%rcx,%r10
	movq	%rdx,%rcx
	movq	%rdx,%r11

	rdtsc
	movl	%eax,%r8d
	movl	$0,%r9d
	clflush	(%r10)
.byte	0xf0
	addl	%r9d,(%r10)
	jmp	.Loop
.p2align	4
.Loop:	rdtsc
	movl	%eax,%edx
	subl	%r8d,%eax
	movl	%edx,%r8d
	movl	%eax,%r9d
	clflush	(%r10)
.byte	0xf0
	addl	%eax,(%r10)
	leaq	4(%r10),%r10
	subq	$1,%rcx
	jnz	.Loop

	movq	%r11,%rax
	.byte	0xf3,0xc3



.globl	OPENSSL_instrument_bus2
.def	OPENSSL_instrument_bus2;	.scl 2;	.type 32;	.endef
.p2align	4
OPENSSL_instrument_bus2:

.byte	243,15,30,250
	movq	%rcx,%r10
	movq	%rdx,%rcx
	movq	%r8,%r11
	movq	%rcx,8(%rsp)

	rdtsc
	movl	%eax,%r8d
	movl	$0,%r9d

	clflush	(%r10)
.byte	0xf0
	addl	%r9d,(%r10)

	rdtsc
	movl	%eax,%edx
	subl	%r8d,%eax
	movl	%edx,%r8d
	movl	%eax,%r9d
.Loop2:
	clflush	(%r10)
.byte	0xf0
	addl	%eax,(%r10)

	subq	$1,%r11
	jz	.Ldone2

	rdtsc
	movl	%eax,%edx
	subl	%r8d,%eax
	movl	%edx,%r8d
	cmpl	%r9d,%eax
	movl	%eax,%r9d
	movl	$0,%edx
	setne	%dl
	subq	%rdx,%rcx
	leaq	(%r10,%rdx,4),%r10
	jnz	.Loop2

.Ldone2:
	movq	8(%rsp),%rax
	subq	%rcx,%rax
	.byte	0xf3,0xc3


.globl	OPENSSL_ia32_rdrand_bytes
.def	OPENSSL_ia32_rdrand_bytes;	.scl 2;	.type 32;	.endef
.p2align	4
OPENSSL_ia32_rdrand_bytes:

.byte	243,15,30,250
	xorq	%rax,%rax
	cmpq	$0,%rdx
	je	.Ldone_rdrand_bytes

	movq	$8,%r11
.Loop_rdrand_bytes:
.byte	73,15,199,242
	jc	.Lbreak_rdrand_bytes
	decq	%r11
	jnz	.Loop_rdrand_bytes
	jmp	.Ldone_rdrand_bytes

.p2align	4
.Lbreak_rdrand_bytes:
	cmpq	$8,%rdx
	jb	.Ltail_rdrand_bytes
	movq	%r10,(%rcx)
	leaq	8(%rcx),%rcx
	addq	$8,%rax
	subq	$8,%rdx
	jz	.Ldone_rdrand_bytes
	movq	$8,%r11
	jmp	.Loop_rdrand_bytes

.p2align	4
.Ltail_rdrand_bytes:
	movb	%r10b,(%rcx)
	leaq	1(%rcx),%rcx
	incq	%rax
	shrq	$8,%r10
	decq	%rdx
	jnz	.Ltail_rdrand_bytes

.Ldone_rdrand_bytes:
	xorq	%r10,%r10
	.byte	0xf3,0xc3


.globl	OPENSSL_ia32_rdseed_bytes
.def	OPENSSL_ia32_rdseed_bytes;	.scl 2;	.type 32;	.endef
.p2align	4
OPENSSL_ia32_rdseed_bytes:

.byte	243,15,30,250
	xorq	%rax,%rax
	cmpq	$0,%rdx
	je	.Ldone_rdseed_bytes

	movq	$8,%r11
.Loop_rdseed_bytes:
.byte	73,15,199,250
	jc	.Lbreak_rdseed_bytes
	decq	%r11
	jnz	.Loop_rdseed_bytes
	jmp	.Ldone_rdseed_bytes

.p2align	4
.Lbreak_rdseed_bytes:
	cmpq	$8,%rdx
	jb	.Ltail_rdseed_bytes
	movq	%r10,(%rcx)
	leaq	8(%rcx),%rcx
	addq	$8,%rax
	subq	$8,%rdx
	jz	.Ldone_rdseed_bytes
	movq	$8,%r11
	jmp	.Loop_rdseed_bytes

.p2align	4
.Ltail_rdseed_bytes:
	movb	%r10b,(%rcx)
	leaq	1(%rcx),%rcx
	incq	%rax
	shrq	$8,%r10
	decq	%rdx
	jnz	.Ltail_rdseed_bytes

.Ldone_rdseed_bytes:
	xorq	%r10,%r10
	.byte	0xf3,0xc3


