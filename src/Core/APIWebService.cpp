/*
 * Copyright 2015 (c) Mark Liversedge (liversedge@gmail.com)
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc., 51
 * Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

#include "APIWebService.h"
#include <QtHttpServer>
#include <QHttpServerResponse>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUrlQuery>
#include <QDir>
#include <QFile>

#include "Context.h"
#include "RideFileCache.h"
#include "RideCache.h"
#include "RideItem.h"
#include "RideMetric.h"
#include "IntervalItem.h"
#include "Colors.h"
#include "Settings.h"
#include "../Metrics/Zones.h"
#include "../Metrics/HrZones.h"
#include "Measures.h"
#include "Zones.h"
#include "RideMetadata.h"
#include "SpecialFields.h"
#include "RideFile.h"

APIWebService::APIWebService(QDir home, QObject *parent) : QObject(parent), home(home)
{
    server = new QHttpServer(this);

    // Root
    server->route("/", []() {
        return "GoldenCheetah API Web Service 1.0";
    });

    // List Athletes
    server->route("/athlete", [this](const QHttpServerRequest &req) {
        return handleListAthletes(req);
    });

    // Athlete specific routes
    server->route("/athlete/<arg>", [this](const QString &athlete, const QHttpServerRequest &req) {
        return handleAthleteRequests(athlete, req);
    });

    // Zones
    server->route("/athlete/<arg>/zones", [this](const QString &athlete, const QHttpServerRequest &req) {
        return handleListZones(athlete, req);
    });

    // Measures
    server->route("/athlete/<arg>/measures", [this](const QString &athlete, const QHttpServerRequest &req) {
       return handleListMeasures(athlete, QString(), req);
    });
    server->route("/athlete/<arg>/measures/<arg>", [this](const QString &athlete, const QString &group, const QHttpServerRequest &req) {
        return handleListMeasures(athlete, group, req);
    });

    // Activity
    server->route("/athlete/<arg>/activity/<arg>", [this](const QString &athlete, const QString &id, const QHttpServerRequest &req) {
        return handleListActivity(athlete, id, req);
    });

    // MMP
    server->route("/athlete/<arg>/meanmax", [this](const QString &athlete, const QHttpServerRequest &req) {
         return handleListMMP(athlete, QString(), req);
    });
    server->route("/athlete/<arg>/meanmax/<arg>", [this](const QString &athlete, const QString &sub, const QHttpServerRequest &req) {
         return handleListMMP(athlete, sub, req);
    });
}

APIWebService::~APIWebService()
{
}

bool APIWebService::start(quint16 port)
{
    if (tcpServer) return false; // already running

    tcpServer = new QTcpServer(this);
    if (!tcpServer->listen(QHostAddress::Any, port)) {
        delete tcpServer;
        tcpServer = nullptr;
        return false;
    }

    server->bind(tcpServer);
    return true; 
}

void APIWebService::stop()
{
    if (tcpServer) {
        tcpServer->close();
        delete tcpServer; // server->bind doesn't take ownership? Docs usually say it doesn't. 
                         // Actually QTcpServer parent is `this`, so it will be deleted on destruction.
                         // For stop(), explicitly closing and deleting is safer to release port.
        tcpServer = nullptr;
    }
}

QHttpServerResponse APIWebService::handleListAthletes(const QHttpServerRequest &request)
{
    Q_UNUSED(request);
    QStringList names;
    names << "*.xml"; // legacy
    names << "*.config"; // current
    
    QByteArray body;

    foreach(QString name, home.entryList(names, QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
        
        // is there a rideDB ?
        QString ridedb = home.absolutePath() + "/" + name + "/cache/rideDB.json";
        if (QFile(ridedb).exists()) {
            QString line = name;
            line += "\n";
            body.append(line.toLocal8Bit());
        }
    }
    
    return QHttpServerResponse("text/csv; charset=ISO-8859-1", body);
}

QHttpServerResponse APIWebService::handleAthleteRequests(const QString &athlete, const QHttpServerRequest &request)
{
    // Check if athlete exists
    if (!QFile(home.absolutePath() + "/" + athlete + "/cache/rideDB.json").exists()) {
        return QHttpServerResponse(QHttpServerResponder::StatusCode::NotFound);
    }
    
    return handleListRides(athlete, request);
}

QHttpServerResponse APIWebService::handleListRides(const QString &athlete, const QHttpServerRequest &request)
{
    QFile ridedb(home.absolutePath() + "/" + athlete + "/cache/rideDB.json");
    if (!ridedb.open(QIODevice::ReadOnly)) {
        return QHttpServerResponse(QHttpServerResponder::StatusCode::NotFound);
    }

    QJsonDocument doc = QJsonDocument::fromJson(ridedb.readAll());
    ridedb.close();
    
    if (!doc.isArray()) {
        return QHttpServerResponse(QHttpServerResponder::StatusCode::InternalServerError);
    }
    QJsonArray rides = doc.array();

    // Parameters
    QUrlQuery q = request.query();
    bool intervals = q.queryItemValue("intervals") == "true";
    QString metrics = q.queryItemValue("metrics");
    QString metadata = q.queryItemValue("metadata");

    listRideSettings settings;
    settings.intervals = intervals;
    
    // Get metric factory for lookup
    const RideMetricFactory &factory = RideMetricFactory::instance();
    
    // Handle ?metrics=NONE for fast directory-only listing
    bool nometrics = false;
    if (metrics.toUpper() == "NONE") {
        nometrics = true;
    } else if (metrics != "") {
        foreach(QString metric, metrics.split(",")) {
            QString name = metric.trimmed();
            if (factory.haveMetric(name)) {
                const RideMetric *m = factory.rideMetric(name);
                settings.wanted << m->index();
            }
        }
    }

    // metadata - support "ALL" like the old implementation with full metadata.xml parsing
    bool nometa = true;
    if (metadata.toUpper() == "ALL") {
        // Load from metadata.xml for full compatibility
        QString metaConfig = home.canonicalPath() + "/metadata.xml";
        if (!QFile(metaConfig).exists()) metaConfig = ":/xml/metadata.xml";
        
        QList<KeywordDefinition> keywordDefinitions;
        QList<FieldDefinition> fieldDefinitions;
        QString colorfield;
        QList<DefaultDefinition> defaultDefinitions;
        
        RideMetadata::readXML(metaConfig, keywordDefinitions, fieldDefinitions, colorfield, defaultDefinitions);
        
        SpecialFields& sp = SpecialFields::getInstance();
        foreach(FieldDefinition field, fieldDefinitions) {
            // don't do metric overrides!
            if(!sp.isMetric(field.name)) settings.metawanted << field.name;
        }
        if (settings.metawanted.count()) nometa = false;
    } else if (metadata != "") {
        foreach(QString meta, metadata.split(",")) settings.metawanted << meta.trimmed();
        if (settings.metawanted.count()) nometa = false;
    }

    QByteArray body;

    // Write CSV header row (matching old implementation)
    body.append("date, time, filename");
    if (settings.intervals) {
        body.append(", interval name, interval type");
    }
    // Add metric headers
    if (settings.wanted.count()) {
        foreach(int index, settings.wanted) {
            QString name = factory.allMetrics().value(index);
            name.replace(" ", "_");
            body.append(QString(", %1").arg(name).toLocal8Bit());
        }
    }
    // Add metadata headers
    foreach(QString meta, settings.metawanted) {
        meta.replace(" ", "_");
        body.append(QString(", \"%1\"").arg(meta).toLocal8Bit());
    }
    body.append("\n");

    // Filters
    QString sincep = q.queryItemValue("since");
    QDate since(1900,01,01);
    if (sincep != "") since = QDate::fromString(sincep,"yyyy/MM/dd");

    QString beforep = q.queryItemValue("before");
    QDate before(3000,01,01);
    if (beforep != "") before = QDate::fromString(beforep,"yyyy/MM/dd");

    // Fast path: if no metrics, no metadata, and no intervals are requested,
    // just traverse the activities directory directly (much faster)
    if (nometrics && nometa && !intervals) {
        return handleListRidesFast(athlete, since, before);
    }

    // Helper to write line
    auto writeLine = [&](RideItem *item) {
        if (settings.intervals) {
             foreach(IntervalItem *interval, item->intervals()){
                body.append(item->dateTime.date().toString("yyyy/MM/dd").toLocal8Bit());
                body.append(", ");
                body.append(item->dateTime.time().toString("hh:mm:ss").toLocal8Bit());
                body.append(", ");
                body.append(item->fileName.toLocal8Bit());
                body.append(", \"");
                body.append(interval->name.toLocal8Bit());
                body.append("\", ");
                body.append(QString("%1").arg(static_cast<int>(interval->type)).toLocal8Bit());

                if (settings.wanted.count()) {
                    foreach(int index, settings.wanted) {
                         // Careful with bounds
                        if (index < interval->metrics().size())
                            body.append(QString(",%1").arg(interval->metrics()[index], 0, 'f').simplified().toLocal8Bit());
                        else body.append(",0");
                    }
                } else {
                    foreach(double value, interval->metrics()) {
                        body.append(QString(",%1").arg(value, 0, 'f').simplified().toLocal8Bit());
                    }
                }
                body.append("\n");
             }
        } else {
            body.append(item->dateTime.date().toString("yyyy/MM/dd").toLocal8Bit());
            body.append(QString(",%1,%2").arg(item->dateTime.time().toString("hh:mm:ss")).arg(item->fileName).toLocal8Bit());

            if (settings.wanted.count()) {
                foreach(int index, settings.wanted) {
                    if (index < item->metrics().size())
                        body.append(QString(",%1").arg(item->metrics()[index], 0, 'f').simplified().toLocal8Bit());
                    else body.append(",0");
                }
            } else {
                foreach(double value, item->metrics()) {
                    body.append(QString(",%1").arg(value, 0, 'f').simplified().toLocal8Bit());
                }
            }

            foreach(QString name, settings.metawanted) {
                QString text = item->getText(name,"");
                text.replace("\"","'");
                text.replace("\n","\\n");
                text.replace("\r","\\r");
                text.replace("\t","\\t");
                body.append(QString(",\"%1\"").arg(text).toLocal8Bit());
            }
            body.append("\n");
        }
    };

    // Iterate
    for (const QJsonValue &val : rides) {
        QJsonObject obj = val.toObject();
        
        QDate d = QDate::fromString(obj["date"].toString(), "yyyy/MM/dd");
        if (d < since || d > before) continue;

        QTime t = QTime::fromString(obj["time"].toString(), "hh:mm:ss");
        QDateTime dt(d, t);
        
        QString filename = obj["filename"].toString();
        
        // Construct temporary RideItem
        RideItem ride(QString(), filename, dt, nullptr, false); 
        
        // Populate from JSON
        // Iterate keys
        for (auto it = obj.begin(); it != obj.end(); ++it) {
            QString key = it.key();
            if (key == "date" || key == "time" || key == "filename") continue;
            
            if (factory.haveMetric(key)) {
                const RideMetric *m = factory.rideMetric(key);
                if (m && m->index() < ride.metrics().size()) {
                    ride.metrics()[m->index()] = it.value().toDouble();
                }
            } else {
                ride.metadata()[key] = it.value().toString();
            }
        }
        
        if (settings.intervals) {
             // We must load the ride file to get intervals
             QString fullPath = home.absolutePath() + "/" + athlete + "/activities/" + filename;
             if (QFile::exists(fullPath)) {
                 QStringList errors;
                 QFile file(fullPath);
                 RideFile *rf = RideFileFactory::instance().openRideFile(nullptr, file, errors);
                 if (rf) {
                     ride.setRide(rf); 
                 }
             }
        }

        writeLine(&ride);
    }

    return QHttpServerResponse("text/csv; charset=ISO-8859-1", body);
}

// Fast path implementation for ?metrics=NONE
QHttpServerResponse APIWebService::handleListRidesFast(const QString &athlete, const QDate &since, const QDate &before)
{
    QByteArray body;
    body.append("date, time, filename\n");
    
    // Fast list of rides by traversing the directory directly
    QDir activities(home.absolutePath() + "/" + athlete + "/activities");
    QStringList names;
    names << "*"; // anything
    
    foreach(QString name, activities.entryList(names, QDir::Files, QDir::Name)) {
        // parse it into date and time
        QDateTime dateTime;
        if (!RideFile::parseRideFileName(name, &dateTime)) continue;
        
        // in range?
        if (dateTime.date() < since || dateTime.date() > before) continue;
        
        // is it a backup?
        if (name.endsWith(".bak")) continue;
        
        // out a line
        body.append(dateTime.date().toString("yyyy/MM/dd").toLocal8Bit());
        body.append(", ");
        body.append(dateTime.time().toString("hh:mm:ss").toLocal8Bit());
        body.append(", ");
        body.append(name.toLocal8Bit());
        body.append("\n");
    }
    
    return QHttpServerResponse("text/csv; charset=ISO-8859-1", body);
}

QHttpServerResponse APIWebService::handleListZones(const QString &athlete, const QHttpServerRequest &request)
{
    // Use JSON for zones as it is hierarchical
    QJsonObject root;
    QJsonObject powerObj;
    QJsonObject hrObj;

    // Power Zones
    QString powerFile = home.absolutePath() + "/" + athlete + "/config/power.zones";
    QFile pf(powerFile);
    if (pf.exists() && pf.open(QIODevice::ReadOnly)) {
        Zones zones;
        zones.read(pf);
        
        QJsonArray ranges;
        for(int i=0; i<zones.getRangeSize(); i++) {
            QJsonObject r;
            r["date"] = zones.getStartDate(i).toString("yyyy/MM/dd");
            r["cp"] = zones.getCP(i);
            r["wprime"] = zones.getWprime(i);
            r["ftp"] = zones.getFTP(i);
            
            QJsonArray zlist;
            QList<int> lows = zones.getZoneLows(i);
            QList<QString> names = zones.getZoneNames(i);
            for(int j=0; j<lows.count(); j++) {
                QJsonObject z;
                z["name"] = names.value(j);
                z["low"] = lows.value(j);
                zlist.append(z);
            }
            r["zones"] = zlist;
            ranges.append(r);
        }
        powerObj["ranges"] = ranges;
    }

    // HR Zones
    QString hrFile = home.absolutePath() + "/" + athlete + "/config/hr.zones";
    QFile hf(hrFile);
    if (hf.exists() && hf.open(QIODevice::ReadOnly)) {
        HrZones zones;
        zones.read(hf);
        
        QJsonArray ranges;
        for(int i=0; i<zones.getRangeSize(); i++) {
            QJsonObject r;
            r["date"] = zones.getStartDate(i).toString("yyyy/MM/dd");
            r["lt"] = zones.getLT(i);
            r["max"] = zones.getMaxHr(i);
            r["rest"] = zones.getRestHr(i);
            
            QJsonArray zlist;
            QList<int> lows = zones.getZoneLows(i);
            QList<QString> names = zones.getZoneNames(i);
            for(int j=0; j<lows.count(); j++) {
                QJsonObject z;
                z["name"] = names.value(j);
                z["low"] = lows.value(j);
                zlist.append(z);
            }
            r["zones"] = zlist;
            ranges.append(r);
        }
        hrObj["ranges"] = ranges;
    }

    root["power"] = powerObj;
    root["heartrate"] = hrObj;

    return QHttpServerResponse(root);
}

QHttpServerResponse APIWebService::handleListMeasures(const QString &athlete, const QString &group, const QHttpServerRequest &request)
{
    Q_UNUSED(request);
    
    QDir athleteDir(home.absolutePath() + "/" + athlete);
    if (!athleteDir.exists()) return QHttpServerResponse(QHttpServerResponder::StatusCode::NotFound);

    Measures measures(athleteDir, true);
    
    QByteArray body;

    // If group is empty, list available groups? Or maybe "Body" is default?
    // Let's iterate all groups if group is empty, or find specific group
    QList<MeasuresGroup*> groups = measures.getGroups();
    
    foreach(MeasuresGroup *g, groups) {
        if (group != "" && g->getName() != group && g->getSymbol() != group) continue;
        
        // Output CSV header
        if (body.isEmpty()) {
            body.append("date");
            QStringList fields = g->getFieldNames();
            foreach(QString f, fields) {
                body.append(",\"");
                body.append(f.toLocal8Bit());
                body.append("\"");
            }
            body.append("\n");
        }

        // Output data
        QList<Measure> &mlo = g->measures();
        foreach(Measure m, mlo) {
            body.append(m.when.date().toString("yyyy/MM/dd").toLocal8Bit());
            for(int i=0; i<g->getFieldNames().count(); i++) {
                 body.append(QString(",%1").arg(m.values[i], 0, 'f').simplified().toLocal8Bit());
            }
            body.append("\n");
        }
    }

    return QHttpServerResponse("text/csv; charset=ISO-8859-1", body);
}

QHttpServerResponse APIWebService::handleListActivity(const QString &athlete, const QString &id, const QHttpServerRequest &request)
{
    bool isJson = false;

    // Fix header access
    QString accept = QString::fromUtf8(request.value("Accept"));
    if (accept.contains("json", Qt::CaseInsensitive)) isJson = true;

    // Load ride
    QString fullPath = home.absolutePath() + "/" + athlete + "/activities/" + id;
    if (!QFile::exists(fullPath)) return QHttpServerResponse(QHttpServerResponder::StatusCode::NotFound);
    
    QStringList errors;
    QFile file(fullPath);
    RideFile *rf = RideFileFactory::instance().openRideFile(nullptr, file, errors);
    if (!rf) return QHttpServerResponse(QHttpServerResponder::StatusCode::InternalServerError);

    // Return as JSON or XML/PWX/etc
    if (isJson) {
         delete rf;
         return QHttpServerResponse(QHttpServerResponder::StatusCode::NotImplemented);
    } else {
        // Return raw file content usually
         QFile f(fullPath);
         if (f.open(QIODevice::ReadOnly)) {
             QByteArray data = f.readAll();
             delete rf;
             return QHttpServerResponse("application/octet-stream", data);
         }
    }
    delete rf;
    return QHttpServerResponse(QHttpServerResponder::StatusCode::InternalServerError);
}

QHttpServerResponse APIWebService::handleListMMP(const QString &athlete, const QString &sub, const QHttpServerRequest &request)
{
    // MMP Logic
    QUrlQuery q = request.query();
    QString seriesp = q.queryItemValue("series");
    if (seriesp == "") seriesp = "watts";
    
    RideFile::SeriesType series;
    if (seriesp == "hr") series = RideFile::hr;
    else if (seriesp == "cad") series = RideFile::cad;
    else if (seriesp == "speed") series = RideFile::kph;
    else if (seriesp == "watts") series = RideFile::watts;
    else if (seriesp == "vam") series = RideFile::vam;
    else if (seriesp == "IsoPower") series = RideFile::IsoPower;
    else if (seriesp == "xPower") series = RideFile::xPower;
    else if (seriesp == "nm") series = RideFile::nm;
    else return QHttpServerResponse(QHttpServerResponder::StatusCode::InternalServerError);

    QByteArray body;
    body.append("secs, ");
    body.append(seriesp.toLocal8Bit());
    body.append("\n");

    if (sub == "bests") {
        QString sincep = q.queryItemValue("since");
        QDate since(1900,01,01);
        if (sincep != "") since = QDate::fromString(sincep,"yyyy/MM/dd");

        QString beforep = q.queryItemValue("before");
        QDate before(3000,01,01);
        if (beforep != "") before = QDate::fromString(beforep,"yyyy/MM/dd");
        
        QVector<float> mmp = RideFileCache::meanMaxFor(home.absolutePath() + "/" + athlete + "/cache", series, since, before);
        
        int secs=1;
        foreach(float value, mmp) {
            body.append(QString("%1, %2\n").arg(secs).arg(value).toLocal8Bit());
            secs++;
        }
    } else {
        return QHttpServerResponse(QHttpServerResponder::StatusCode::NotImplemented);
    }
    
    return QHttpServerResponse("text/csv; charset=ISO-8859-1", body);
}
