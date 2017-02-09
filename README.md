# NAME

PsiBlastHelper - It's modulino that splits fasta input file into number of chunks for BLAST, PSI-BLAST and HMMER. It also writes SGE and HTCondor scripts to run these jobs on cluster or grid.

# SYNOPSIS

    # run separately for BLAST and HMMER because application path changes

    # test example for BLAST and PSI-BLAST
    lib/PsiBlastHelper.pm --infile=t/data/dm_splicvar \
    --out=t/data/dm_chunks/ --chunk_name=dm --chunk_size=50 --fasta_size 3000 \
    --cpu 5 --cpu_l 5 \
    --db_name=dbfull --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz \
    --email=msestak@irb.hr --app_path=/home/msestak/ncbi-blast-2.5.0+/bin/

    # test example for HMMER
    lib/PsiBlastHelper.pm --infile=t/data/dm_splicvar \
    --out=t/data/dm_chunks/ --chunk_name=dm --chunk_size=50 --fasta_size 3000 \
    --cpu 5 --cpu_l 5 \
    --db_name=dbfull --db_path=/shared/msestak/dbfull --db_gz_name=dbfull.gz \
    --email=msestak@irb.hr --app_path=/home/msestak/hmmer-3.1b2-linux-intel-x86_64/binaries/

    # possible options for BLAST database
    --db_name=dbfull  --db_path=/shared/msestak/db_full_plus --db_gz_name=dbfull_plus_format_new.tar.gz
    --db_name=db90    --db_path=/shared/msestak/db90_plus    --db_gz_name=db90_plus_format_new.tar.gz
    --db_name=db90old --db_path=/shared/msestak/db90old      --db_gz_name=db90old_format.tar.gz

    # options for HMMER database
    --db_name=dbfull  --db_path=/shared/msestak/dbfull --db_gz_name=dbfull.gz

# DESCRIPTION

PsiBlastHelper is modulino that splits fasta file (input) into a number of chunks for high throughput BLAST+, PSI-BLAST+ or HMMER.
Chunks get short name + different number for each chunk (+ sufix '\_large' if larger than --fasta\_size or in top N sequences by size). This is because BLAST works really slowly for large sequences and they are processed separately one by one.
So you need to provide input file, size of the chunk, chunk name and either top N or length of sequences to run separately. 
You also meed to provide --cpu or --cpu\_l to split SGE or HTCondor script on this number of jobs. The idea here is to reduce a number of BLAST database copies, which can lead to failed jobs if out of disk space on specific node. This means that one script == one database copy and multiple BLAST processes.
You can also use -a (--append) to append remainder of sequences to last file or to create new file with this remainder, which is default.
After splitting sequences it prints SGE and HTCondor jobs bash scripts.
All paths are hardcoded to ISABELLA cluster at tannat.srce.hr and CRO-NGI grid.

For help write:

    perl FastaSplit.pm -h
    perl FastaSplit.pm -m

Summary of options:

\--infile (fasta file with proteins to be split)
\--out (directory where chunks and scripts will be written, recreated if it exists)
\--chunk\_name (first part of the fasta chunk name, e.g., "dm" means that chunks dm1, dm2, dm3, ... will be created)
\--chunk\_size (number of fasta sequences per chunk)
\--fasta\_size (length of fasta sequence after which sequences will be run one by one due to problems with BLAST buffers, usually 3000)
\--cpu (number of BLAST jobs to run per one script for "normal" sequences, i.e., sequences with less than 3000 aminoacids)
\--cpu\_l (number of BLAST jobs to run per one script for "long" sequences, i.e., sequences with more than 3000 aminoacids)
\--db\_name (name of the BLAST database to be used in BLAST command)
\--db\_path (path to BLAST database on tannat.srce.hr; recomendation is to put it on /shared/user/ path because of the infiniband connection to nodes; Isabella specific)
\--db\_gz\_name (name of the BLAST database on home directory on grid for CRO NGI jobs, not used on Isabella)
\--email (email address to send notifications when jobs start, abort or end)
\--app\_path (path to the blastp, phammer or psiblast executable)

Optional:
\--append (append last remainder of sequences to last chunk file, default create new file)
\--top (top N largest sequences to run one by one)
\--v (verbose; by default logging level is INFO; -v sets it to DEBUG; -v -v sets it to TRACE)
\--q (quiet; opposite of verbose; run without logging to terminal; it still writes full log to file)
\--grid\_address (specify address of grid center other than ce.srce.cro-ngi.hr, specific to HTCondor)

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Martin Sebastijan Šestak <martin.s.sestak@gmail.com>
