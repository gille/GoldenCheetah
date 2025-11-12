#include <QtTest>
#include "Cloud/GoogleDrive.h"

class GoogleDriveHelpersTest : public QObject
{
	Q_OBJECT
private slots:
	void testMakeQStringRoot();
	void testMakeQStringParent();
};

void GoogleDriveHelpersTest::testMakeQStringRoot()
{
	QString q = GoogleDrive::MakeQString("");
	QVERIFY2(q.startsWith("q="), "Query must start with q=");
	QVERIFY2(q.contains("root"), "Root parents query should target root");
}

void GoogleDriveHelpersTest::testMakeQStringParent()
{
	QString parent = "abc123";
	QString q = GoogleDrive::MakeQString(parent);
	QVERIFY2(q.contains(parent), "Parent id should be included in query");
}

QTEST_MAIN(GoogleDriveHelpersTest)
#include "tst_googleDrive.moc"


