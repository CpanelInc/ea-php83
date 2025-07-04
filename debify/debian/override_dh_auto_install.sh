#!/bin/bash

source debian/vars.sh

set -x

mkdir -p $DEB_INSTALL_ROOT/opt/cpanel/ea-php83

install -d $DEB_INSTALL_ROOT/usr/local/bin
ln -sf /opt/cpanel/ea-php83/root/usr/bin/php $DEB_INSTALL_ROOT/usr/local/bin/ea-php83
install -d $DEB_INSTALL_ROOT/usr/bin
ln -sf /opt/cpanel/ea-php83/root/usr/bin/php-cgi $DEB_INSTALL_ROOT/usr/bin/ea-php83

pushd build
make INSTALL_ROOT=$DEB_INSTALL_ROOT install-sapi install install-headers install-fpm
popd

# Install the default configuration file and icons
install -m 755 -d $DEB_INSTALL_ROOT$_sysconfdir/
install -m 644 $SOURCE2 $DEB_INSTALL_ROOT$_sysconfdir/php.ini
# For third-party packaging:
install -m 755 -d $DEB_INSTALL_ROOT$_datadir/php
install -m 755 -d $DEB_INSTALL_ROOT$_sysconfdir/php.d
install -m 755 -d $DEB_INSTALL_ROOT$_localstatedir/lib
install -m 755 build/sapi/litespeed/lsphp $DEB_INSTALL_ROOT$_bindir/lsphp
# PHP-FPM stuff
# Log
# we need to do the following to compensate for the way
# EA4 on OBS was built rather than EA4-Opensuse
install -d $DEB_INSTALL_ROOT/opt/cpanel/$ns_name-$pkg/root/usr/var/log/php-fpm
mkdir -p $DEB_INSTALL_ROOT$_localstatedir/log/php-fpm
mkdir -p $DEB_INSTALL_ROOT$_localstatedir/run/php-fpm
install -d $DEB_INSTALL_ROOT/opt/cpanel/$ns_name-$pkg/root/usr/var/run/php-fpm
ln -sf /opt/cpanel/$ns_name-$pkg/root/usr/var/log/php-fpm $DEB_INSTALL_ROOT$_localstatedir/log/php-fpm
ln -sf /opt/cpanel/$ns_name-$pkg/root/usr/var/run/php-fpm $DEB_INSTALL_ROOT$_localstatedir/run/php-fpm
# Config
install -m 755 -d $DEB_INSTALL_ROOT$_sysconfdir/php-fpm.d
install -m 644 $SOURCE4 $DEB_INSTALL_ROOT$_sysconfdir/php-fpm.conf
sed -e "s:/run:$_localstatedir/run:" \
    -e "s:/var/log:$_localstatedir/log:" \
    -e "s:/etc:$_sysconfdir:" \
    -i $DEB_INSTALL_ROOT$_sysconfdir/php-fpm.conf
install -m 644 $SOURCE5 $DEB_INSTALL_ROOT$_sysconfdir/php-fpm.d/www.conf
sed -e "s:/var/lib:$_localstatedir/lib:" \
    -e "s:/var/log:$_localstatedir/log:" \
    -i $DEB_INSTALL_ROOT$_sysconfdir/php-fpm.d/www.conf
mv $DEB_INSTALL_ROOT$_sysconfdir/php-fpm.d/www.conf $DEB_INSTALL_ROOT$_sysconfdir/php-fpm.d/www.conf.example
mv ${DEB_INSTALL_ROOT}opt/cpanel/ea-php83/root/etc/php-fpm.conf.default .
# tmpfiles.d
# install -m 755 -d $DEB_INSTALL_ROOT$_prefix/lib/tmpfiles.d
# install -m 644 php-fpm.tmpfiles $DEB_INSTALL_ROOT$_prefix/lib/tmpfiles.d/php-fpm.conf
# install systemd unit files and scripts for handling server startup
install -m 755 -d $DEB_INSTALL_ROOT$_unitdir
install -m 644 $SOURCE6 $DEB_INSTALL_ROOT$_unitdir/${scl_prefix}php-fpm.service
sed -e "s:/run:$_localstatedir/run:" \
    -e "s:/etc:$_sysconfdir:" \
    -e "s:/usr/sbin:$_sbindir:" \
    -i $DEB_INSTALL_ROOT$_unitdir/${scl_prefix}php-fpm.service
# LogRotate
install -m 755 -d $DEB_INSTALL_ROOT/etc/logrotate.d
install -m 644 $SOURCE7 $DEB_INSTALL_ROOT/etc/logrotate.d/${scl_prefix}php-fpm
sed -e "s:/run:$_localstatedir/run:" \
    -e "s:/var/log:$_localstatedir/log:" \
    -i $DEB_INSTALL_ROOT/etc/logrotate.d/${scl_prefix}php-fpm
# Environment file
install -m 755 -d $DEB_INSTALL_ROOT$_sysconfdir/sysconfig
echo "SOURCE8 :$SOURCE8:"
install -m 644 $SOURCE8 $DEB_INSTALL_ROOT$_sysconfdir/sysconfig/php-fpm
mkdir -p ${DEB_INSTALL_ROOT}$_sysconfdir/php.d

# make the cli commands available in standard root for SCL build
# Generate files lists and stub .ini files for each subpackage
for mod in pgsql odbc ldap snmp xmlrpc imap \
    mysqlnd mysqli pdo_mysql \
    mbstring gd dom xsl soap bcmath dba xmlreader xmlwriter \
    simplexml bz2 calendar ctype exif ftp gettext gmp iconv \
    sockets tokenizer opcache \
    pdo pdo_pgsql pdo_odbc json \
    pdo_sqlite sqlite3 \
    enchant \
    phar fileinfo \
    intl \
    tidy \
    sodium \
    zip \
    pspell curl xml \
    posix shmop sysvshm sysvsem sysvmsg
do
    # for extension load order
    case $mod in
      opcache)
        # Zend extensions
        ini=10-${mod}.ini;;
      pdo_*|mysqli|xmlreader|xmlrpc)
        # Extensions with dependencies on 20-*
        ini=30-${mod}.ini;;
      *)
        # Extensions with no dependency
        ini=20-${mod}.ini;;
    esac
    # Some extensions have their own config file
    #
    # NOTE: rpmlint complains about the spec file using $_sourcedir macro.
    #       However, our usage acceptable given the transient nature of the ini files.
    #       https://fedoraproject.org/wiki/Packaging:RPM_Source_Dir?rd=PackagingDrafts/RPM_Source_Dir
    if [ -f "$buildroot/$ini" ]; then
      cp -p $buildroot/$ini ${DEB_INSTALL_ROOT}$_sysconfdir/php.d/$ini
    else
      cat > ${DEB_INSTALL_ROOT}$_sysconfdir/php.d/$ini <<EOF
; Enable ${mod} extension module
extension=${mod}.so
EOF
    fi
    cat > files.${mod} <<EOF
EOF
done
# The dom, xsl and xml* modules are all packaged in php-xml
cat files.dom files.xsl files.xml{reader,writer} \
    files.simplexml >> files.xml
# mysqlnd
cat files.mysqli \
    files.pdo_mysql \
    >> files.mysqlnd
# Split out the PDO modules
cat files.pdo_pgsql >> files.pgsql
cat files.pdo_odbc >> files.odbc
# sysv* packaged in php-process
cat files.shmop files.sysv* > files.process
cat files.pdo_sqlite >> files.pdo
cat files.sqlite3 >> files.pdo
# Package json and phar in -common.
cat files.json files.phar \
    files.ctype \
    files.tokenizer > files.common
# The default Zend OPcache blacklist file
install -m 644 $SOURCE51 $DEB_INSTALL_ROOT$_sysconfdir/php.d/opcache-default.blacklist
# Install the macros file:
install -d $DEB_INSTALL_ROOT/$_sysconfdir/rpm
install -m 644 -c macros.php \
           $DEB_INSTALL_ROOT$_sysconfdir/rpm/macros.$name
# Remove unpackaged files
rm -rf $DEB_INSTALL_ROOT$_libdir/php/modules/*.a \
       $DEB_INSTALL_ROOT$_bindir/{phptar} \
       $DEB_INSTALL_ROOT$_datadir/pear \
       $DEB_INSTALL_ROOT$_libdir/libphp7.la
# Remove irrelevant docs
rm -f README.{Zeus,QNX,CVS-RULES}

# The CONFIG/INSTALL script misses these files

gzip debian/tmp/opt/cpanel/ea-php83/root/usr/share/man/man1/phar.1
gzip debian/tmp/opt/cpanel/ea-php83/root/usr/share/man/man1/phar.phar.1
gzip debian/tmp/opt/cpanel/ea-php83/root/usr/share/man/man1/php-cgi.1
gzip debian/tmp/opt/cpanel/ea-php83/root/usr/share/man/man1/php.1
gzip debian/tmp/opt/cpanel/ea-php83/root/usr/share/man/man1/phpize.1
gzip debian/tmp/opt/cpanel/ea-php83/root/usr/share/man/man1/phpdbg.1
gzip debian/tmp/opt/cpanel/ea-php83/root/usr/share/man/man1/phpconfig.1
gzip debian/tmp/opt/cpanel/ea-php83/root/usr/share/man/man1/php-config.1
gzip debian/tmp/opt/cpanel/ea-php83/root/usr/share/man/man8/php-fpm.8

cp -f ./debian/tmp/etc/php-fpm.conf ./debian/tmp/opt/cpanel/ea-php83/root/etc/php-fpm.conf

mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-dbg-${pkg_php_version}
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-dbg-${pkg_php_version}
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-fpm-${pkg_php_version}
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/licenses/ea-php83-php-fpm-${pkg_php_version}
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/licenses/ea-php83-php-bcmath-${pkg_php_version}
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-mbstring-${pkg_php_version}
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc/php-fpm.d
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc/php.d
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/var/run/php-fpm
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/var/log/php-fpm
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc/sysconfig/php-fpm
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/php
mkdir -p ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/var/lib

cp -R ${DEB_INSTALL_ROOT}/etc/php-fpm.d ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc/php-fpm.d
cp -f ./sapi/phpdbg/CREDITS ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-dbg-${pkg_php_version}
cp -f ./sapi/phpdbg/README.md ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-dbg-${pkg_php_version}
cp -f ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc/php-fpm.d/php-fpm.d/www.conf.example ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc/php-fpm.d
cp -R ${DEB_INSTALL_ROOT}/etc/sysconfig/php-fpm ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc/sysconfig
cp -R ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc/php-fpm.conf.default ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-fpm-${pkg_php_version}
cp -R ./fpm_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-fpm-${pkg_php_version}
cp ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/etc/php.d/* ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc/php.d
cp ${DEB_INSTALL_ROOT}/etc/php.ini ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/etc
cp ./CODING_STANDARDS.md ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./EXTENSIONS ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./NEWS ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./README.REDIST.BINS ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./README.md ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./TSRM_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./Zend/ZEND_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./libmagic_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./php.ini-development ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./php.ini-production ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}
cp ./fpm_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/licenses/ea-php83-php-fpm-${pkg_php_version}
cp ./libmbfl_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-mbstring-${pkg_php_version}
cp ./libbcmath_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/licenses/ea-php83-php-bcmath-${pkg_php_version}
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-dbg-${pkg_php_version}/CREDITS ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-dbg/CREDITS
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-fpm-${pkg_php_version}/php-fpm.conf.default ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-fpm/php-fpm.conf.default
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-fpm-${pkg_php_version}/fpm_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/licenses/ea-php83-php-fpm/fpm_LICENSE
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/CODING_STANDARDS.md ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/CODING_STANDARDS.md
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/EXTENSIONS ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/EXTENSIONS
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/LICENSE
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/NEWS ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/NEWS
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/README.REDIST.BINS ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/README.REDIST.BINS
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/README.md ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/README.md
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/TSRM_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/TSRM_LICENSE
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/ZEND_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/ZEND_LICENSE
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/libmagic_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/libmagic_LICENSE
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/php.ini-development ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/php.ini-development
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-${pkg_php_version}/php.ini-production ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/php.ini-production
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-mbstring-${pkg_php_version}/libmbfl_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-mbstring/libmbfl_LICENSE
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/licenses/ea-php83-php-bcmath-${pkg_php_version}/libbcmath_LICENSE ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/licenses/ea-php83-php-bcmath/libbcmath_LICENSE
install -DT ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common-8.2.0rc3/README.md ${DEB_INSTALL_ROOT}/opt/cpanel/ea-php83/root/usr/share/doc/ea-php83-php-common/README.md

echo "FILELIST"
find . -type f -print

